require "neo4j"
require "logger"

require "./models"
require "./moku/config"
require "./db/pool"

module DB
  DRIVER = Neo4j.connect(URI.parse(ENV["NEO4J_URL"]), ssl: !!ENV["NEO4J_SSL"]?)

  spawn ensure_indexes!
  spawn run_migrations!

  class Exception < ::Exception
  end
  class PoolTimeout < Exception
  end

  abstract struct Query
    LOGGER = Logger.new(STDOUT, level: Logger::DEBUG)

    def self.call(*args, **kwargs)
      new.call(*args, **kwargs)
    end

    def self.call(*args, **kwargs, &)
      new.call(*args, **kwargs) { |row| yield row }
    end

    def self.[](*args, **kwargs)
      new.call(*args, **kwargs)
    end

    def initialize(@driver : Neo4j::Cluster | Neo4j::DirectDriver = DRIVER)
    end

    private def write_transaction(&block : Neo4j::Bolt::Transaction -> T) forall T
      @driver.write_transaction { |txn| yield txn }
    end

    private def read_transaction(&block : Neo4j::Bolt::Transaction -> T) forall T
      @driver.read_transaction { |txn| yield txn }
    end

    # exec_cast(query, {User, Group}, user_id: params["id"])
    private def exec_cast(_query : String, _types : Tuple(*TYPES), **params) forall TYPES
      exec_cast _query, _types, Neo4j::Map.from(params)
    end

    private def exec_cast(_query : String, _types : Tuple(*TYPES), **params, &) forall TYPES
      exec_cast _query, _types, Neo4j::Map.from(params) do |row|
        yield row
      end
    end

    private def read_query(query, as types : Tuple(*T)) forall T
      session(&.read_transaction(&.exec_cast(query, types)))
    end

    private def read_query(query, as types : Tuple(*T), parameters : Neo4j::Map) forall T
      session(&.read_transaction(&.exec_cast(query, parameters, types)))
    end

    private def read_query(query : String) : Nil
      session(&.read_transaction(&.execute(query)))
    end

    private def read_query(_query query, as types : Tuple(*T), **params, &) forall T
      session(&.read_transaction(&.exec_cast(query, params, types) { |row| yield row }))
    end

    private def read_query(_query query, as types : Tuple(*T), **params) forall T
      session(&.read_transaction(&.exec_cast(query, params, types)))
    end

    private def write_query(query : String, as types : Tuple(*T), **parameters) forall T
      session(&.write_transaction(&.exec_cast(query, parameters, types)))
    end

    private def exec_cast(query : String, types : Tuple(*TYPES), params : Neo4j::Map, &) forall TYPES
      start = Time.utc
      count = 0
      session do |session|
        error = nil
        session.exec_cast query, params, types do |row|
          count += 1
          yield row unless error

        # We need to receive all of the results, so let's just keep going until
        # we pull everything, but remember that we had an error.
        rescue ex
          error = ex
        end

        if error
          raise error
        end
      end
    ensure
      LOGGER.debug do
        {
          query: self.class.name,
          cypher: query,
          types: types,
          params: params,
          result_count: count,
          execution_time: Time.utc - start.not_nil!,
        }
      end
    end

    private def exec_cast(query : String, types : Tuple(*TYPES), params : Neo4j::Map) forall TYPES
      start = Time.utc
      results = session do |session|
        session.exec_cast query, params, types
      end
    ensure
      LOGGER.debug do
        {
          query: self.class.name,
          cypher: query,
          types: types,
          params: params,
          result_count: results.try(&.size),
          execution_time: Time.utc - start.not_nil!,
        }
      end
    end

    private def execute(_query : String, **params)
      start = Time.utc
      results = session(&.execute(_query, **params))
    ensure
      LOGGER.debug do
        {
          query: self.class.name,
          cypher: _query,
          params: params,
          result_count: results.try(&.size),
          execution_time: Time.utc - start.not_nil!,
        }
      end
    end

    private def session(& : Neo4j::Session -> T) forall T
      @driver.session { |session| yield session }
    end

    class Exception < ::DB::Exception
    end
    class NotFound < Exception
    end
  end

  struct GetLocalAccountWithID < Query
    def call(id : String) : LocalAccount?
      user = nil
      read_query <<-CYPHER, {LocalAccount}, id: id do |(account)|
        MATCH (acct:LocalAccount { id: $id })
        RETURN acct
        LIMIT 1
      CYPHER
        user = account
      end

      user
    end
  end

  struct GetLocalAccountWithEmail < Query
    def call(email : String) : LocalAccount?
      user = nil
      read_query <<-CYPHER, {LocalAccount}, email: email do |(account)|
        MATCH (acct:LocalAccount { email: $email })
        RETURN acct
        LIMIT 1
      CYPHER
        user = account
      end

      user
    end
  end

  struct GetLocalAccountWithHandle < Query
    def call(handle : String) : LocalAccount?
      user = nil
      read_query <<-CYPHER, {LocalAccount}, handle: handle do |(account)|
        MATCH (acct:LocalAccount { handle: $handle })
        RETURN acct
        LIMIT 1
      CYPHER
        user = account
      end

      user
    end
  end

  struct GetTimelineFor < Query
    def call(user_id : String, older_than : Time? = nil, newer_than : Time? = nil, max limit = 25, &)
      read_query(
        <<-CYPHER,
          WITH datetime({ year: 1990 }) AS oldest_time_we_care_about

          MATCH (acct:LocalAccount { id: $id })
          MATCH (acct)-[:SUBSCRIBED_TO]->(stream:Stream)
          MATCH (note)-[:POSTED_IN]->(stream)

          WITH DISTINCT note, oldest_time_we_care_about, acct

          OPTIONAL MATCH (boosted_by)-[boosted:BOOSTED]->(note)

          WITH note, boosted_by, boosted, coalesce(boosted.at, note.created_at) AS timestamp, acct

          WHERE timestamp < coalesce($older_than, datetime())
          AND timestamp > coalesce($newer_than, oldest_time_we_care_about)

          WITH note, boosted_by, boosted, acct
          ORDER BY timestamp DESC
          LIMIT $limit

          MATCH (author:Account)-[:POSTED]->(note)
          OPTIONAL MATCH (note)-[:HAS_POLL_OPTION]->(poll_option)
          OPTIONAL MATCH (note)-[:HAS_ATTACHMENT]->(attachment)
          OPTIONAL MATCH (acct)-[i_liked:LIKED]->(note)
          OPTIONAL MATCH (acct)-[i_boosted:BOOSTED]->(note)

          RETURN note, author, boosted_by, collect(attachment) AS attachments, boosted.at, collect(poll_option) AS poll_options, i_liked IS NOT NULL AS i_liked, i_boosted IS NOT NULL AS i_boosted
        CYPHER
        {Note, Account, Account?, Array(Attachment), Time?, Array(PollOption), Bool, Bool},
        id: user_id,
        older_than: older_than,
        newer_than: newer_than,
        limit: limit,
      ) { |row| yield row }
    end
  end

  struct GetNoteWithID < Query
    def call(id : URI) : Note?
      read_query(<<-CYPHER, {Note}, Neo4j::Map { "id" => id.to_s }).first?.try(&.first)
        MATCH (note:Note { id: $id })
        RETURN note
        LIMIT 1
      CYPHER
    end
  end

  struct GetNotesInStream < Query
    def call(id : String, current_user_id : URI? = nil, limit = 1_000_000)
      read_query <<-CYPHER, {Note, Account, Array(Attachment), Array(PollOption), Bool, Bool}, id: id, current_user_id: current_user_id ? current_user_id.to_s : nil, limit: limit do |row|
        MATCH (stream:Stream { id: $id })
        MATCH (note)-[:POSTED_IN]->(stream)
        MATCH (author:Account)-[:POSTED]->(note)
        OPTIONAL MATCH (note)-[:HAS_ATTACHMENT]->(attachment)
        OPTIONAL MATCH (note)-[:HAS_POLL_OPTION]->(poll_option)

        WITH note, author, attachment, poll_option
        ORDER BY note.created_at DESC

        OPTIONAL MATCH (current_user:LocalAccount { id: $current_user_id })
        OPTIONAL MATCH (current_user)-[i_liked:LIKED]->(note)
        OPTIONAL MATCH (current_user)-[i_boosted:BOOSTED]->(note)

        RETURN note, author, collect(attachment) AS attachments, collect(poll_option) AS poll_options, i_liked IS NOT NULL AS i_liked, i_boosted IS NOT NULL AS i_boosted
        LIMIT $limit
      CYPHER
        yield row
      end
    end
  end

  struct GetThreadFor < Query
    def call(id : URI, current_user : LocalAccount?)
      read_query <<-CYPHER, {Note, Account, Array(Attachment), Bool, Bool}, id: id.to_s, current_user_id: current_user.try(&.id.to_s) do |row|
        MATCH (selected:Note { id: $id })
        MATCH (note:Note)
        WHERE (note)-[:IN_REPLY_TO*0..]->(selected)
        OR (selected)-[:IN_REPLY_TO*0..]->(note)

        WITH note

        MATCH (author:Account)-[:POSTED]->(note)
        OPTIONAL MATCH (note)-[:HAS_ATTACHMENT]->(attachment)

        OPTIONAL MATCH (current_user:LocalAccount { id: $current_user_id })
        OPTIONAL MATCH (current_user)-[i_liked:LIKED]->(note)
        OPTIONAL MATCH (current_user)-[i_boosted:BOOSTED]->(note)

        RETURN DISTINCT note, author, collect(attachment) AS attachments, i_liked IS NOT NULL AS i_liked, i_boosted IS NOT NULL AS i_boosted
        ORDER BY note.created_at
      CYPHER
        yield row
      end
    end
  end

  struct GetAccountWithPublicKeyAndAttachments < Query
    def call(handle : String) : {Account, String, Array(Attachment)}
      if row = read_query(<<-CYPHER, {Account, String, Array(Attachment)}, handle: handle).first?
        MATCH (acct:LocalAccount { handle: $handle })
        MATCH (acct)-[:HAS_KEY_PAIR]->(key_pair)
        OPTIONAL MATCH (acct)-[:HAS_ATTACHMENT]->(attachment)

        RETURN acct, key_pair.public_key, collect(attachment) AS attachments
      CYPHER
        row
      else
        raise NotFound.new("No account found with the handle #{handle.inspect}")
      end
    end
  end

  struct GetAccount < Query
    def call(id : URI) : Account?
      if row = read_query(<<-CYPHER, {Account}, id: id.to_s).first?
        MATCH (acct:Account { id: $id })
        RETURN acct
        LIMIT 1
      CYPHER
        row.first
      end
    end
  end

  struct GetFollowersForAccount < Query
    def call(handle : String) : Array(Account | PartialAccount)
      accounts = Array(Account | PartialAccount).new

      read_query <<-CYPHER, {Account | PartialAccount}, handle: handle do |(account)|
        MATCH (follower:Person)-[:FOLLOWS]->(account:Account)
        WHERE account.handle = $handle
        RETURN follower
      CYPHER
        accounts << account
      end

      accounts
    end
  end

  struct GetPostCountForAccount < Query
    def call(handle : String) : Int64
      read_query(<<-CYPHER, {Int64}, handle: handle).first.first
        MATCH (:LocalAccount { handle: $handle })-[:POSTED]->(post)
        RETURN count(post)
      CYPHER
    end
  end

  struct GetFollowerCountForAccount < Query
    def call(handle : String) : Int64
      read_query(<<-CYPHER, {Int64}, handle: handle).first.first
        MATCH (follower:Account)-[:FOLLOWS]->(account:Account)
        WHERE account.handle = $handle
        RETURN count(follower)
      CYPHER
    end
  end

  struct GetFollowingForAccount < Query
    def call(handle : String) : Array(Account)
      accounts = Array(Account).new

      read_query <<-CYPHER, {Account}, handle: handle do |(account)|
        MATCH (follower:Account)-[:FOLLOWS]->(account:Account)
        WHERE follower.handle = $handle
        RETURN account
      CYPHER
        accounts << account
      end

      accounts
    end
  end

  struct GetFollowingCountForAccount < Query
    def call(handle : String) : Int64
      read_query(<<-CYPHER, {Int64}, handle: handle).first.first
        MATCH (follower:Account)-[:FOLLOWS]->(account:Account)
        WHERE follower.handle = $handle
        RETURN count(account)
      CYPHER
    end
  end

  struct GetKeyPairForAccount < Query
    def call(uri : URI) : OpenSSL::RSA::KeyPair
      node = execute(<<-CYPHER, account_id: uri.to_s).first.first.as(Neo4j::Node)
        MATCH (account:Account { id: $account_id })-[:HAS_KEY_PAIR]->(keypair)
        RETURN keypair
      CYPHER

      OpenSSL::RSA::KeyPair.new(
        public_key: node.properties["public_key"].as(String),
        private_key: node.properties["private_key"].as(String),
      )
    end
  end

  struct OutboxCollectionItemsForAccount < Query
    def call(handle : String, older_than timestamp : Time) : Array(Note)
      notes = Array(Note).new

      read_query <<-CYPHER, {Note}, handle: handle, timestamp: timestamp do |(note)|
        MATCH (account:Account { handle: $handle })
        MATCH (account)-[:HAS_OUTBOX_STREAM]->(stream)
        MATCH (note)-[:POSTED_IN]->(stream)
        WHERE note.created_at < $timestamp
        RETURN note
        ORDER BY note.created_at DESC
        LIMIT 50
      CYPHER
        notes << note
      end

      notes
    end
  end

  struct OutboxCollectionCountForAccount < Query
    def call(handle : String) : Int64
      read_query(<<-CYPHER, {Int64}, handle: handle).first.first
        MATCH (account:Account { handle: $handle })
        MATCH (account)-[:HAS_OUTBOX_STREAM]->(stream)
        MATCH (note)-[:POSTED_IN]->(stream)
        RETURN count(note)
      CYPHER
    end
  end

  struct RequestToFollowUser < Query
    def call(follower_handle : String, followee_id : String)
      execute <<-CYPHER, follower_handle: follower_handle, followee_id: followee_id
        MATCH (follower:LocalAccount { handle: $follower_handle })
        WITH follower

        MERGE (followee:Person { id: $followee_id })
          ON CREATE SET
            followee:PartialAccount,
            followee.created_at = datetime(),
            followee.updated_at = datetime()

        MERGE (follower)-[request:WANTS_TO_FOLLOW]->(followee)
        ON CREATE SET request.sent_at = datetime()
      CYPHER
    end
  end

  struct ConfirmFollowUser < Query
    def call(follower_handle : String, followee_id : URI, followers_stream : URI)
      execute <<-CYPHER, follower_handle: follower_handle, followee_id: followee_id.to_s, followers_stream_id: followers_stream.to_s
        MATCH (follower:LocalAccount { handle: $follower_handle })
        WITH follower

        MERGE (followee:Person { id: $followee_id })
          ON CREATE SET
            followee:PartialAccount,
            followee.created_at = datetime(),
            followee.updated_at = datetime()
        WITH follower, followee

        OPTIONAL MATCH (follower)-[intent:WANTS_TO_FOLLOW]->(followee)

        MERGE (follower)-[follow:FOLLOWS]->(followee)
        ON CREATE SET follow.since = datetime()

        MERGE (stream:Stream { id: $followers_stream_id })
        MERGE (follower)-[:SUBSCRIBED_TO]->(stream)

        DELETE intent

        RETURN followee, follower, follow
      CYPHER
    end
  end

  struct AcceptFollowRequest < Query
    def call(follower_id : URI, followee_id : URI)
      execute <<-CYPHER, follower_id: follower_id.to_s, followee_id: followee_id.to_s
        MATCH (followee:LocalAccount { id: $followee_id })
        WITH followee

        MERGE (follower:Person { id: $follower_id })
          ON CREATE SET
            follower:PartialAccount,
            follower.created_at = datetime(),
            follower.updated_at = datetime()
        WITH follower, followee

        OPTIONAL MATCH (follower)-[intent:WANTS_TO_FOLLOW]->(followee)

        MERGE (follower)-[follow:FOLLOWS]->(followee)
        ON CREATE SET follow.since = datetime()

        DELETE intent

        RETURN followee, follower, follow
      CYPHER
    end
  end

  struct AlreadyFollows < Query
    def call(follower_id : URI, followee_id : URI) : Bool
      read_query(<<-CYPHER, {Bool}, follower_id: follower_id.to_s, followee_id: followee_id.to_s).first.first
        OPTIONAL MATCH (follower:Account { id: $follower_id })
        OPTIONAL MATCH (followee:Account { id: $followee_id })

        OPTIONAL MATCH (follower)-[follow:FOLLOWS|WANTS_TO_FOLLOW]->(followee)

        RETURN follow IS NOT NULL
        LIMIT 1
      CYPHER
    end

    def call(follower_id : Nil, followee_id : URI) : Bool
      false
    end
  end

  struct UnfollowAccount < Query
    def call(follower_id : URI, followee_id : URI)
      execute <<-CYPHER, follower_id: follower_id.to_s, followee_id: followee_id.to_s
        MATCH (follower:Account { id: $follower_id })-[follow:FOLLOWS|WANTS_TO_FOLLOW]->(followee:Account { id: $followee_id })

        DELETE follow
      CYPHER
    end
  end

  struct CreateLocalAccount < Query
    def call(
      id : URI,
      handle : String,
      name : String,
      email : String,
      password : Crypto::Bcrypt::Password,
      public_key : String,
      private_key : String,
      followers_url : URI = id.dup.tap { |uri| uri.path += "/followers" },
      outbox_url : URI = id.dup.tap { |uri| uri.path += "/outbox" },
      inbox_url : URI = id.dup.tap { |uri| uri.path += "/inbox" },
      shared_inbox : URI = id.dup.tap { |uri| uri.path = "/inbox" },
      _labels = %w[Account LocalAccount Person],
    ) : LocalAccount
      result = write_query <<-CYPHER, {LocalAccount},
        CREATE (acct:#{_labels.join(':')} {
          id: $id,
          handle: $handle,
          display_name: $name,
          email: $email,
          password: $password,
          summary: "",
          manually_approves_followers: false,
          followers_url: $followers_url,
          shared_inbox: $shared_inbox,
          inbox_url: $inbox_url,
          discoverable: true,
          created_at: datetime(),
          updated_at: datetime()
        })
        CREATE (kp:KeyPair {
          public_key: $public_key,
          private_key: $private_key,
          created_at: datetime()
        })
        CREATE (acct)-[:HAS_SELF_STREAM]->(stream:Stream { id: $id })
        CREATE (acct)-[:HAS_FOLLOWERS_STREAM]->(followers_stream:Stream { id: $followers_url })
        CREATE (acct)-[:SUBSCRIBED_TO]->(followers_stream)
        CREATE (acct)-[:HAS_OUTBOX_STREAM]->(:Stream { id: $outbox_url })

        CREATE (acct)-[:HAS_KEY_PAIR]->(kp)
        RETURN acct
      CYPHER
        handle: handle,
        name: name,
        id: id.to_s,
        email: email,
        password: password.to_s,
        followers_url: followers_url.to_s,
        shared_inbox: shared_inbox.to_s,
        outbox_url: outbox_url.to_s,
        inbox_url: inbox_url.to_s,
        public_key: public_key,
        private_key: private_key

      result.first.first
    end
  end

  struct PostNoteFromAccount < Query
    def call(
      account_id : URI,
      id : URI,
      content : String,
      created_at : Time,
      to : Array(String),
      cc : Array(String),
      url : URI,
      in_reply_to : URI?,
      summary : String? = nil,
      attachments : Array(ActivityPub::Object | ActivityPub::Activity) = Array(ActivityPub::Object | ActivityPub::Activity).new,
      sensitive : Bool = false,
      type : String = "Note",
      poll_options : Array(ActivityPub::Object)? = nil,
    )
      execute <<-CYPHER,
        MERGE (acct:Person { id: $account_id })
          ON CREATE SET acct:PartialAccount

        WITH acct

        OPTIONAL MATCH (acct)-[:HAS_OUTBOX_STREAM]->(outbox)
        MERGE (note:Replyable { id: $id })
          ON CREATE SET
            note.created_at = $created_at
        REMOVE
          note:PartialReplyable
        SET
          note:Note,
          note.content = $content,
          note.summary = $summary,
          note.to = $to,
          note.cc = $cc,
          note.sensitive = $sensitive,
          note.url = $url,
          note.type = $type

        // Add this note as a reply to the specified one
        FOREACH (ignored IN CASE $in_reply_to WHEN NULL THEN [] ELSE [1] END |
          MERGE (in_reply_to:Replyable { id: $in_reply_to })
            ON CREATE SET in_reply_to:PartialReplyable
          MERGE (note)-[:IN_REPLY_TO]->(in_reply_to)
          SET note:Reply
        )
        // If $in_reply_to is nil, we mark it as an original post
        FOREACH (ignored IN CASE $in_reply_to WHEN NULL THEN [1] ELSE [] END |
          SET note:OriginalPost
        )
        // I wish Cypher had a more expressive approach for this, tbh, but
        // unfortunately CASE is only for expressions and Cypher doesn't let you
        // use it for side effects, so we have to do the FOREACH/CASE hack.

        MERGE (acct)-[:POSTED]->(note)
        WITH note, outbox

        UNWIND filter(stream IN $to + $cc + [outbox.id] WHERE stream IS NOT NULL) AS stream_id
        MERGE (stream:Stream { id: stream_id })
        MERGE (note)-[:POSTED_IN]->(stream)

        FOREACH (poll_option in $poll_options |
          MERGE (note)-[:HAS_POLL_OPTION]->(option:PollOption { name: poll_option.name })
            SET option.vote_count = poll_option.vote_count
        )

        WITH DISTINCT note
        UNWIND $attachments AS attachment
        MERGE (att:Attachment {
          type: attachment.type,
          media_type: attachment.media_type,
          url: attachment.url
        })
          ON CREATE SET att.created_at = datetime()
        MERGE (note)-[:HAS_ATTACHMENT]->(att)
      CYPHER
        account_id: account_id.to_s,
        id: id.to_s,
        content: content,
        created_at: created_at,
        summary: summary || "",
        to: to.map(&.as(Neo4j::Value)),
        cc: cc.map(&.as(Neo4j::Value)),
        sensitive: sensitive,
        url: url.to_s,
        in_reply_to: in_reply_to && in_reply_to.to_s,
        attachments: attachments.map { |attachment|
          Neo4j::Map {
            "type" => attachment.type,
            "media_type" => attachment.media_type,
            "url" => attachment.url.to_s,
          }.as(Neo4j::Value)
        },
        poll_options: (poll_options || Array(ActivityPub::Object).new).map { |option|
          Neo4j::Map {
            "name" => option.name,
            "vote_count" => (option.replies.try(&.total_items) || 0).to_i64,
          }.as Neo4j::Value
        },
        type: type # Not sure if this will ever be needed, but it might be useful
    end
  end

  struct BoostNote < Query
    def call(actor_id : URI, note : ActivityPub::Object, announcement : ActivityPub::Activity)
      execute <<-CYPHER,
        MATCH (actor:Account { id: $actor_id })
        MERGE (op:Person { id: $op_id })
          ON CREATE SET op:PartialAccount

        MERGE (op)-[:POSTED]->(note:Note {
          id: $note_properties.id,
          type: $note_properties.type,
          summary: $note_properties.summary,
          content: $note_properties.content,
          created_at: $note_properties.created_at,
          url: $note_properties.url,
          to: $note_properties.to,
          cc: $note_properties.cc,
          sensitive: $note_properties.sensitive
        })
        MERGE (actor)-[boost:BOOSTED]->(note)
          ON CREATE SET
            boost.at = datetime(),
            boost.id = $boost_id

        WITH note
        UNWIND $announcement.to + $announcement.cc AS stream_id
        MERGE (stream:Stream { id: stream_id })
        MERGE (note)-[:POSTED_IN]->(stream)

        WITH note
        UNWIND $attachments AS attachment
        MERGE (att:Attachment {
          type: attachment.type,
          media_type: attachment.media_type,
          url: attachment.url
        })
          ON CREATE SET att.created_at = datetime()
        MERGE (note)-[:HAS_ATTACHMENT]->(att)
      CYPHER
        actor_id: actor_id.to_s,
        op_id: note.attributed_to.as(URI).to_s,
        boost_id: announcement.id.as(URI).to_s,
        announcement: Neo4j::Map {
          "to" => announcement.to.as(Array).map(&.as(Neo4j::Value)),
          "cc" => announcement.cc.as(Array).map(&.as(Neo4j::Value)),
        },
        note_properties: Neo4j::Map {
          "id" => note.id.to_s,
          "type" => note.type,
          "summary" => note.summary || "",
          "content" => note.content,
          "created_at" => note.published,
          "url" => note.url.to_s,
          "to" => note.to.as(Array).map(&.as(Neo4j::Value)),
          "cc" => note.cc.as(Array).map(&.as(Neo4j::Value)),
          "sensitive" => note.sensitive,
        },
        attachments: note.attachment.as(Array).map { |attachment|
          attachment = attachment.as(ActivityPub::Activity | ActivityPub::Object)
          Neo4j::Map {
            "media_type" => attachment.media_type,
            "url" => attachment.url.to_s,
            "type" => attachment.type,
          }.as(Neo4j::Value)
        }
    end
  end

  struct UndoBoost < Query
    def call(actor_id : URI, note_id : URI)
      execute <<-CYPHER, actor_id: actor_id.to_s, note_id: note_id.to_s
        MATCH (acct:Account { id: $actor_id })
        MATCH (stream:Stream { id: acct.followers_url })
        MATCH (note:Note { id: $note_id })

        MATCH (account)-[boost:BOOSTED]->(note)-[post:POSTED_IN]->(stream)

        DELETE boost, post
      CYPHER
    end
  end

  struct IsAlreadyLikedBy < Query
    def call(note_id : URI, actor : LocalAccount)
      read_query(<<-CYPHER, {Bool}, note_id: note_id.to_s, actor_id: actor.id.to_s).first.first
        OPTIONAL MATCH (:LocalAccount { id: $actor_id })-[like:LIKED]->(:Note { id: $note_id })
        RETURN like IS NOT NULL AS liked
        LIMIT 1
      CYPHER
    end

    def call(note_id : URI, actor : Nil)
      false
    end
  end

  struct IsAlreadyBoostedBy < Query
    def call(note_id : URI, actor : LocalAccount) : URI?
      read_query(<<-CYPHER, {String?}, note_id: note_id.to_s, actor_id: actor.id.to_s).first.first.try { |id| URI.parse id }
        OPTIONAL MATCH (:LocalAccount { id: $actor_id })-[boost:BOOSTED]->(:Note { id: $note_id })
        RETURN boost.id
        LIMIT 1
      CYPHER
    end

    def call(note_id : URI, actor : Nil)
      false
    end
  end

  struct AuthorOf < Query
    def call(note_id : URI)
      read_query(<<-CYPHER, {Account}, note_id: note_id.to_s).first.first
        MATCH (author:Account)-[:POSTED]->(:Note { id: $note_id })
        RETURN author
      CYPHER
    end
  end

  struct DeleteNote < Query
    def call(note_id : URI, actor_id : URI)
      execute <<-CYPHER,
        MATCH (acct:Account { id: $actor_id })-[action:POSTED]->(note:Note { id: $note_id })-[stream_entry:POSTED_IN]->(stream)
        OPTIONAL MATCH (note)-[attach:HAS_ATTACHMENT]->(attachment)
        OPTIONAL MATCH (note)-[reply:IN_REPLY_TO]->()

        DELETE action, note, stream_entry, attach, attachment, reply
      CYPHER
        note_id: note_id.to_s,
        actor_id: actor_id.to_s
    end
  end

  struct DeleteObject < Query
    def call(object_id : URI)
      execute <<-CYPHER, object_id: object_id.to_s
        MATCH (object { id: $object_id })
        DETACH DELETE object
      CYPHER
    end
  end

  struct Like < Query
    def call(actor_id : URI, object_id : URI)
      execute <<-CYPHER,
        MATCH (acct:Account { id: $actor_id })
        MATCH (object:Note { id: $object_id }) // TODO: Make this more than a Note!

        MERGE (acct)-[:LIKED]->(object)
        SET object.like_count = coalesce(object.like_count, 0) + 1
      CYPHER
        actor_id: actor_id.to_s,
        object_id: object_id.to_s
    end
  end

  struct Unlike < Query
    def call(actor_id : URI, object_id : URI)
      execute <<-CYPHER,
        MATCH (acct:Account)-[like:LIKED|LIKES]->(object)
        WHERE acct.id = $actor_id
        AND object.id = $object_id

        DELETE like
        SET object.like_count = object.like_count - 1
      CYPHER
        actor_id: actor_id.to_s,
        object_id: object_id.to_s
    end
  end

  struct NotesForAccount < Query
    def call(account_id : URI)
      read_query(<<-CYPHER, {Account, Array(Note)}, id: account_id.to_s).first
        MATCH (acct:Account { id: $id })
        OPTIONAL MATCH (acct)-[:POSTED]->(note)

        RETURN acct, collect(note) AS notes
      CYPHER
    end
  end

  struct PartialAccountIDs < Query
    def call
      uris = Array(URI).new

      read_query <<-CYPHER, {String} do |(url)|
        MATCH (partial:PartialAccount)
        RETURN partial.id
      CYPHER
        uris << URI.parse(url)
      rescue ex
        pp ex
      end

      uris
    end
  end

  struct PartialReplyableIDs < Query
    def call
      uris = Array(URI).new

      read_query <<-CYPHER, {String} do |(url)|
        MATCH (partial:PartialReplyable)
        RETURN partial.id
      CYPHER
        uris << URI.parse(url)
      rescue ex
        pp ex
      end

      uris
    end
  end

  struct UpdatePerson < Query
    def call(account : ::Account)
      # transaction do |txn|
        execute <<-CYPHER,
          MERGE (person:Person { id: $id })
            ON CREATE SET person.created_at = datetime()

          MERGE (followers:Stream { id: $followers_url })
          MERGE (person)-[:HAS_FOLLOWERS_STREAM]->(followers)

          MERGE (inbox:Stream { id: $inbox_url })
          MERGE (person)-[:HAS_INBOX_STREAM]->(inbox)

          SET
            person.display_name = $display_name,
            person.handle = $handle,
            person.summary = $summary,
            person.manually_approves_followers = $manually_approves_followers,
            person.followers_url = $followers_url,
            person.inbox_url = $inbox_url,
            person.discoverable = $discoverable,
            person.shared_inbox = $shared_inbox,
            person.icon = $icon,
            person.image = $image,
            person.updated_at = datetime(),
            person:Account,
            person:#{account.id.host == Moku::SELF.host ? "LocalAccount" : "RemoteAccount"}

          REMOVE person:PartialAccount
        CYPHER
          id: account.id.to_s,
          display_name: account.display_name,
          handle: account.handle,
          summary: account.summary,
          followers_url: account.followers_url.to_s,
          inbox_url: account.inbox_url.to_s,
          manually_approves_followers: account.manually_approves_followers?,
          discoverable: account.discoverable?,
          shared_inbox: account.shared_inbox.to_s,
          icon: account.icon.to_s,
          image: account.image.to_s
      # end
    end
  end

  struct GetNodeInfo < Query
    def call : NodeInfo
      result = read_query(<<-CYPHER, {Int32, Int32, Int32, Int32, Bool, Bool}).first
        MATCH (all_accts:LocalAccount)
        WITH DISTINCT all_accts

        OPTIONAL MATCH (monthly_active:LocalAccount)-[:POSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 1 })
        WITH DISTINCT all_accts, count(distinct monthly_active) as posts_in_last_month

        OPTIONAL MATCH (half_yearly_active:LocalAccount)-[:POSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 6 })
        WITH DISTINCT all_accts, posts_in_last_month, count(distinct half_yearly_active) as posts_in_last_half_year

        OPTIONAL MATCH (monthly_active:LocalAccount)-[:BOOSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 1 })
        WITH DISTINCT all_accts, posts_in_last_month, posts_in_last_half_year, count(distinct monthly_active) as boosts_in_last_month

        OPTIONAL MATCH (half_yearly_active:LocalAccount)-[:POSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 6 })
        WITH DISTINCT all_accts, posts_in_last_month, posts_in_last_half_year, boosts_in_last_month, count(distinct half_yearly_active) as boosts_in_last_half_year

        OPTIONAL MATCH (all_accts)-[:POSTED]->(local_post)
        OPTIONAL MATCH (all_accts)-[:BOOSTED]->(local_boost)

        RETURN
          count(all_accts) AS total_users,
          posts_in_last_month + boosts_in_last_month AS monthly_active,
          posts_in_last_half_year + boosts_in_last_half_year AS half_yearly_active,
          count(local_post) + count(local_boost) AS local_posts,
          true AS open_registrations,
          false AS approval_required
      CYPHER

      NodeInfo.new(*result)
    end

    record NodeInfo,
      total_users : Int32,
      monthly_active_users : Int32,
      half_yearly_active_users : Int32,
      local_posts : Int32,
      open_registrations : Bool,
      approval_required : Bool
  end

  struct ListAdmins < Query
    def call(limit = 10) : Array(LocalAccount)
      admins = Array(LocalAccount).new

      read_query <<-CYPHER, {LocalAccount}, limit: limit do |(admin)|
        MATCH (admin:Admin)
        RETURN admin
        LIMIT $limit
      CYPHER
        admins << admin
      end

      admins
    end
  end

  struct Search < Query
    alias Result = Note | Account

    def call(query : String, searcher : LocalAccount?) : Array({Result, Account?, Bool})
      read_query <<-CYPHER, {Result, Account?, Bool}, query: query, my_id: searcher.try(&.id.to_s)
        CALL db.index.fulltext.queryNodes('search_everything', $query) YIELD node, score
        MATCH (node)
        OPTIONAL MATCH (account)-[:POSTED]->(node)
        OPTIONAL MATCH (:LocalAccount { id: $my_id })-[follow:FOLLOWS]->(node)
        RETURN node, account, follow IS NOT NULL
        ORDER BY score DESC
      CYPHER
    end
  end

  def self.ensure_indexes!
    puts "Ensuring indexes..."
    DRIVER.session(&.write_transaction { |txn|
      # Unique indexes
      {
        LocalAccount: %w[id handle email],
        Account: %w[id],
        RemoteAccount: %w[id],
        Person: %w[id],
        PartialAccount: %w[id],
        Note: %w[id],
        Replyable: %w[id],
        PartialReplyable: %w[id],
        Stream: %w[id],
      }.each do |label, properties|
        properties.each do |property|
          txn.execute <<-CYPHER.tap { |query| puts query }
            CREATE CONSTRAINT ON (n:#{label}) ASSERT n.#{property} IS UNIQUE
          CYPHER
        end
      end

      {
        Note: %w[created_at],
      }.each do |label, properties|
        properties.each do |property|
          txn.execute <<-CYPHER.tap { |query| puts query }
            CREATE INDEX ON :#{label}(#{property})
          CYPHER
        end
      end

      # Existence constraints
      {
        Account: %w[display_name handle],
        LocalAccount: %w[email password],
        Note: %w[id],
        Stream: %w[id],
        Person: %w[id],
      }.each do |label, properties|
        properties.each do |property|
          txn.execute <<-CYPHER.tap { |query| puts query }
            CREATE CONSTRAINT ON (n:#{label}) ASSERT exists(n.#{property})
          CYPHER
        end
      end

      begin
        # txn.execute <<-CYPHER.tap { |query| puts query }
        #   CALL db.index.fulltext.createNodeIndex(
        #     'search_everything',
        #     ['Note', 'Account'],
        #     ['display_name', 'handle', 'content', 'summary', 'id'],
        #     { analyzer: 'english' }
        #   )
        # CYPHER
      rescue ex : Neo4j::IndexAlreadyExists
        # We're good
      end
    })
  end

  def self.run_migrations!
    puts "Running data migrations..."
    DRIVER.session(&.write_transaction { |txn|
      txn.execute <<-CYPHER
        MATCH (acct:LocalAccount)

        MERGE (stream:Stream { id: acct.id })
        MERGE (followers_stream:Stream { id: acct.followers_url })
        MERGE (outbox:Stream { id: acct.id + '/outbox' })

        MERGE (acct)-[:HAS_SELF_STREAM]->(stream)
        MERGE (acct)-[:HAS_FOLLOWERS_STREAM]->(followers_stream)
        MERGE (acct)-[:SUBSCRIBED_TO]->(followers_stream)
        MERGE (acct)-[:HAS_OUTBOX_STREAM]->(outbox)

        WITH acct, outbox
        OPTIONAL MATCH (acct)-[:POSTED]->(note)
        WITH collect(note) AS notes, outbox
        UNWIND notes AS note
        MERGE (note)-[:POSTED_IN]->(outbox)
      CYPHER

      txn.execute <<-CYPHER
        MATCH (follower:LocalAccount)-[:FOLLOWS]->(account)-[:HAS_FOLLOWERS_STREAM]->(stream)
        MERGE (follower)-[:SUBSCRIBED_TO]->(stream)
      CYPHER

      txn.execute <<-CYPHER
        MATCH (partial:PartialReplyable)
        WITH partial

        OPTIONAL MATCH (note:Note { id: partial.id })
        DETACH DELETE note

        RETURN partial.id
      CYPHER

      txn.execute <<-CYPHER
        MATCH (note:Note)
        WHERE NOT note:Replyable
        SET note:Replyable
      CYPHER
    })
  end
end

class Hash(K, V)
  def self.from(nt : NamedTuple)
    nt.each_with_object(new) do |key, value, hash|
      hash[key.to_s] = value
    end
  end
end

struct NamedTuple
  def each_with_object(obj : T) : T forall T
    each do |key, value|
      yield key, value, obj
    end
    obj
  end
end

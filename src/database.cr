require "neo4j"
require "pool/connection"
require "logger"

require "./models"
require "./moku/config"
require "./db/pool"

module DB
  NEO4J_POOL = Pool(Neo4j::Bolt::Connection).new(max_idle_pool_size: 50) do
    Neo4j::Bolt::Connection.new(ENV["NEO4J_URL"], ssl: !!ENV["NEO4J_SSL"]?)
  end

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

    def initialize(@pool : Pool(Neo4j::Bolt::Connection) = NEO4J_POOL)
    end

    def transaction(&block : Neo4j::Bolt::Transaction -> T) forall T
      connection do |connection|
        connection.transaction { |txn| block.call txn }
      end
    end

    def connection
      @pool.connection { |c| yield c }
    end

    # exec_cast(query, {User, Group}, user_id: params["id"])
    def exec_cast(_query : String, _types : Tuple(*TYPES), **params) forall TYPES
      LOGGER.debug do
        String.build do |str|
          str.puts "CYPHER"
          str.puts _query
          str.puts _types.pretty_inspect
          str.puts params.pretty_inspect
        end
      end
      connection do |connection|
        connection.exec_cast _query, params, _types
      end
    end

    def exec_cast(_query : String, _types : Tuple(*TYPES), **params, &) forall TYPES
      LOGGER.debug do
        String.build do |str|
          str.puts "CYPHER"
          str.puts _query
          str.puts _types.pretty_inspect
          str.puts params.pretty_inspect
        end
      end
      connection do |connection|
        connection.exec_cast _query, params, _types do |row|
          yield row
        end
      end
    end

    def exec_cast(query : String, types : Tuple(*TYPES), params : NamedTuple) forall TYPES
      LOGGER.debug do
        String.build do |str|
          str.puts "CYPHER"
          str.puts query
          str.puts types.pretty_inspect
          str.puts params.pretty_inspect
        end
      end
      connection do |connection|
        connection.exec_cast query, params, types do |row|
          yield row
        end
      end
    end

    def execute(_query : String, **params)
      LOGGER.debug do
        String.build do |str|
          str.puts "CYPHER"
          str.puts _query
          str.puts params.pretty_inspect
        end
      end
      connection(&.execute(_query, **params))
    end

    class Exception < ::DB::Exception
    end
    class NotFound < Exception
    end
  end

  struct GetLocalAccountWithID < Query
    def call(id : String) : LocalAccount?
      user = nil
      exec_cast <<-CYPHER, {LocalAccount}, id: id do |(account)|
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
      exec_cast <<-CYPHER, {LocalAccount}, email: email do |(account)|
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
      exec_cast <<-CYPHER, {LocalAccount}, handle: handle do |(account)|
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
    def call(user_id : String, &)
      exec_cast <<-CYPHER, {Note, Account, Account?, Array(Attachment)}, id: user_id do |row|
        MATCH (acct:LocalAccount { id: $id })
        MATCH (acct)-[:SUBSCRIBED_TO]->(stream:Stream)
        MATCH (note)-[:POSTED_IN]->(stream)
        MATCH (author)-[:POSTED]->(note)
        OPTIONAL MATCH (boosted_by)-[boosted:BOOSTED]->(note)
        OPTIONAL MATCH (note)-[:HAS_ATTACHMENT]->(attachment)

        WITH note, author, boosted_by, attachment
        ORDER BY coalesce(boosted.at, note.created_at) DESC

        RETURN note, author, boosted_by, collect(attachment) AS attachments
      CYPHER
        yield row
      end
    end
  end

  struct GetNotesInStream < Query
    def call(id : String)
      exec_cast <<-CYPHER, {Note, Account, Array(Attachment)}, id: id do |row|
        MATCH (stream:Stream { id: $id })
        MATCH (note)-[:POSTED_IN]->(stream)
        MATCH (author)-[:POSTED]->(note)
        OPTIONAL MATCH (note)-[:HAS_ATTACHMENT]->(attachment)

        WITH note, author, attachment
        ORDER BY note.created_at DESC

        RETURN note, author, collect(attachment) AS attachments
      CYPHER
        yield row
      end
    end
  end

  struct GetAccountWithPublicKeyAndAttachments < Query
    def call(handle : String) : {Account, String, Array(Attachment)}
      if row = exec_cast(<<-CYPHER, {Account, String, Array(Attachment)}, handle: handle).first?
        MATCH (acct:Account { handle: $handle })
        OPTIONAL MATCH (acct)-[:HAS_KEY_PAIR]->(key_pair)
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
      if row = exec_cast(<<-CYPHER, {Account}, id: id.to_s).first?
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

      exec_cast <<-CYPHER, {Account | PartialAccount}, handle: handle do |(account)|
        MATCH (follower:Person)-[:FOLLOWS]->(account:Account)
        WHERE account.handle = $handle
        RETURN follower
      CYPHER
        accounts << account
      end

      accounts
    end
  end

  struct GetFollowerCountForAccount < Query
    def call(handle : String) : Int64
      exec_cast(<<-CYPHER, {Int64}, handle: handle).first.first
        MATCH (follower:Account)-[:FOLLOWS]->(account:Account)
        WHERE account.handle = $handle
        RETURN count(follower)
      CYPHER
    end
  end

  struct GetFollowingForAccount < Query
    def call(handle : String) : Array(Account)
      accounts = Array(Account).new

      exec_cast <<-CYPHER, {Account}, handle: handle do |(account)|
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
      exec_cast(<<-CYPHER, {Int64}, handle: handle).first.first
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

      exec_cast <<-CYPHER, {Note}, handle: handle, timestamp: timestamp do |(note)|
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
      exec_cast(<<-CYPHER, {Int64}, handle: handle).first.first
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

        MERGE (follower)-[:WANTS_TO_FOLLOW { sent_at: datetime() }]->(followee)
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

  struct Unfollow < Query
    def call(follower_id : URI, followee_id : URI)
      execute <<-CYPHER, follower_id: follower_id.to_s, followee_id: followee_id.to_s
        MATCH (follower:Account { id: $follower_id })-[follow:FOLLOWS]->(followee:Account { id: $followee_id })

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
      shared_inbox : URI = id.dup.tap { |uri| uri.path = "/inbox" },
      _labels = %w[Account LocalAccount Person],
    ) : Account
      result = exec_cast <<-CYPHER, {Account},
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
      summary : String? = nil,
      attachments : Array(ActivityPub::Object | ActivityPub::Activity) = Array(ActivityPub::Object | ActivityPub::Activity).new,
      sensitive : Bool = false,
      type : String = "Note",
    )
      execute <<-CYPHER,
        MATCH (acct:Person { id: $account_id })
        OPTIONAL MATCH (acct)-[:HAS_OUTBOX_STREAM]->(outbox)
        MERGE (note:Note { id: $id })
          ON CREATE SET
            note.content = $content,
            note.created_at = $created_at,
            note.summary = $summary,
            note.to = $to,
            note.cc = $cc,
            note.sensitive = $sensitive,
            note.url = $url,
            note.type = $type

        MERGE (acct)-[:POSTED]->(note)
        WITH note, outbox

        UNWIND filter(stream IN $to + $cc + [outbox.id] WHERE stream IS NOT NULL) AS stream_id
        MERGE (stream:Stream { id: stream_id })
        MERGE (note)-[:POSTED_IN]->(stream)

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
        attachments: attachments.map { |attachment|
          Neo4j::Map {
            "type" => attachment.type,
            "media_type" => attachment.media_type,
            "url" => attachment.url.to_s,
          }.as(Neo4j::Value)
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
          ON CREATE SET boost.at = datetime()

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

  struct DeleteNote < Query
    def call(note_id : URI, actor_id : URI)
      execute <<-CYPHER,
        MATCH (acct:Account { id: $actor_id })-[action:POSTED]->(note:Note { id: $note_id })-[stream_entry:POSTED_IN]->(stream)
        MATCH (note)-[attach:HAS_ATTACHMENT]->(attachment)

        DELETE action, note, stream_entry, attach, attachment
      CYPHER
        note_id: note_id.to_s,
        actor_id: actor_id.to_s
    end
  end

  struct NotesForAccount < Query
    def call(account_id : URI)
      exec_cast(<<-CYPHER, {Account, Array(Note)}, id: account_id.to_s).first
        MATCH (acct:Account { id: $id })
        OPTIONAL MATCH (acct)-[:POSTED]->(note)

        RETURN acct, collect(note) AS notes
      CYPHER
    end
  end

  struct PartialAccountIDs < Query
    def call
      uris = Array(URI).new

      exec_cast <<-CYPHER, {String}, NamedTuple.new do |(url)|
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
            person:#{account.id.host == URI.parse(Moku::SELF).host ? "LocalAccount" : "RemoteAccount"}

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
      result = exec_cast(<<-CYPHER, {Int32, Int32, Int32, Int32, Bool}).first
        MATCH (all_accts:LocalAccount)
        WITH all_accts

        OPTIONAL MATCH (monthly_active:LocalAccount)-[:POSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 1 })
        OPTIONAL MATCH (half_yearly_active)-[:BOOSTED]->(boosted)
        WHERE boosted.created_at > datetime() - duration({ months: 6 })
        WITH all_accts, monthly_active

        OPTIONAL MATCH (half_yearly_active:LocalAccount)-[:POSTED]->(note)
        WHERE note.created_at > datetime() - duration({ months: 6 })
        OPTIONAL MATCH (half_yearly_active)-[:BOOSTED]->(boosted)
        WHERE boosted.created_at > datetime() - duration({ months: 6 })
        WITH all_accts, monthly_active, half_yearly_active

        OPTIONAL MATCH (all_accts)-[:POSTED]->(local_post)
        OPTIONAL MATCH (all_accts)-[:BOOSTED]->(local_boost)

        RETURN
          count(all_accts) AS total_users,
          count(monthly_active) AS monthly_active,
          count(half_yearly_active) AS half_yearly_active,
          count(local_post) + count(local_boost) AS local_posts,
          true AS open_registrations
      CYPHER

      NodeInfo.new(*result)
    end

    record NodeInfo,
      total_users : Int32,
      monthly_active_users : Int32,
      half_yearly_active_users : Int32,
      local_posts : Int32,
      open_registrations : Bool
  end

  struct Search < Query
    alias Result = Note | Account

    def call(query : String) : Array({Result, Account?})
      exec_cast <<-CYPHER, {Result, Account?}, query: query
        CALL db.index.fulltext.queryNodes('search_everything', $query) YIELD node, score
        MATCH (node)
        OPTIONAL MATCH (account)-[:POSTED]->(node)
        RETURN node, account
        ORDER BY score DESC
      CYPHER
    end
  end

  def self.ensure_indexes!
    puts "Ensuring indexes..."
    NEO4J_POOL.connection do |connection|
      # Unique indexes
      {
        LocalAccount: %w[handle email],
        RemoteAccount: %w[handle email],
        Note: %w[id],
        Stream: %w[id],
        Person: %w[id],
      }.each do |label, properties|
        properties.each do |property|
          connection.execute <<-CYPHER.tap { |query| puts query }
            CREATE CONSTRAINT ON (n:#{label}) ASSERT n.#{property} IS UNIQUE
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
          connection.execute <<-CYPHER.tap { |query| puts query }
            CREATE CONSTRAINT ON (n:#{label}) ASSERT exists(n.#{property})
          CYPHER
        end
      end

      begin
        # connection.execute <<-CYPHER.tap { |query| puts query }
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
    end
  end

  def self.run_migrations!
    puts "Running data migrations..."
    NEO4J_POOL.connection do |connection|
      connection.execute <<-CYPHER
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

      connection.execute <<-CYPHER
        MATCH (follower:LocalAccount)-[:FOLLOWS]->(account)-[:HAS_FOLLOWERS_STREAM]->(stream)
        MERGE (follower)-[:SUBSCRIBED_TO]->(stream)
      CYPHER
    end
  end
end

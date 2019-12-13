require "../database"
require "./fetch_replyable"

module Moku
  module Services
    struct ReifyPartialReplyables
      def self.call
        new.call
      end

      def call
        DB::PartialReplyableIDs.call.each do |id|
          spawn FetchReplyable.new.call(id)
        end
      end
    end
  end
end

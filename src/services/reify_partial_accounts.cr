require "../database"

module Moku
  module Services
    struct ReifyPartialAccounts
      def self.call
        new.call
      end

      def call
        DB::PartialAccountIDs.call.each do |id|
          spawn FetchRemoteAccount.new.call(id)
        end
      end
    end
  end
end

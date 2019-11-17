require "../spec_helper"
require "../db_helper"

require "../../src/services/fetch_remote_account"
require "../../src/database"

module Moku::Services
  describe FetchRemoteAccount do
    it "fetches an account when there isn't an existing account at all" do
      id = "https://zomglol.wtf/users/jamie"
      DB.execute "MATCH (n:Person { id: $id }) DETACH DELETE n", id: id

      fetch = FetchRemoteAccount.new
      fetch.call(URI.parse(id))

      count = DB.exec_cast_scalar "MATCH (n:RemoteAccount { id: $id }) RETURN count(n)", {Int32}, id: id
      count.should eq 1
    end

    it "fetches an account when there is an existing account" do
      id = "https://zomglol.wtf/users/jamie"
      DB.execute "MATCH (n:Person { id: $id }) DETACH DELETE n", id: id
      DB.execute "MERGE (n:Person:PartialAccount { id: $id })", id: id

      fetch = FetchRemoteAccount.new
      fetch.call(URI.parse(id))

      count = DB.exec_cast_scalar "MATCH (n:RemoteAccount { id: $id }) RETURN count(n)", {Int32}, id: id
      count.should eq 1
    end
  end
end

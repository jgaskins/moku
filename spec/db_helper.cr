require "../src/database"

module DB
  def self.execute(_query, **params)
    NEO4J_POOL.connection(&.execute(_query, **params))
  end

  def self.exec_cast(_query, types, **params)
    NEO4J_POOL.connection(&.exec_cast(_query, params, types))
  end

  def self.exec_cast_scalar(_query, type, **params)
    NEO4J_POOL.connection(&.exec_cast(_query, params, type)).first.first
  end

  Query::LOGGER.level = Logger::WARN
end

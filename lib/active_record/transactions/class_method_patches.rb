::ActiveRecord::Transactions::ClassMethods.module_eval do

  #  We need to override transaction method as FiberConnectionPool is likely to give us a new connection
  #  for every subsequent statement within BEGIN .. COMMIT block, leading to cryptic MySQL errors.
  #
  def transaction(options = {}, &block)
    connection.with_reserved_connection do
      connection.transaction(options, &block)
    end
  end

end
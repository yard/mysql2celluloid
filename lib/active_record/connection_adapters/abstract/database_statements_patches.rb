#  It seems that abstract connection adapter is assuming the only concurrency it will ever face
#  is none :) Therefore, we need to isolate transactions and ensure they are per-Fiber as well.
#
::ActiveRecord::ConnectionAdapters::DatabaseStatements.module_eval do
  
  def current_transaction
    @connection.gathered_data[:transaction] ||= ::ActiveRecord::ConnectionAdapters::ClosedTransaction.new(self)
  end

  def current_transaction=(value)
    @connection.gathered_data[:transaction] = value if @connection
  end

  def transaction_open?
    current_transaction.open?
  end

  def begin_transaction(options = {})
    self.current_transaction = current_transaction.begin(options)
  end

  def commit_transaction #:nodoc:
    self.current_transaction = current_transaction.commit
  end

  def rollback_transaction #:nodoc:
    self.current_transaction = current_transaction.rollback
  end

  def reset_transaction #:nodoc:
    self.current_transaction = ::ActiveRecord::ConnectionAdapters::ClosedTransaction.new(self)
  end

  # Register a record with the current transaction so that its after_commit and after_rollback callbacks
  # can be called.
  #
  def add_transaction_record(record)
    self.current_transaction.add_record(record)
  end

end
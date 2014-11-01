require 'active_record'
require 'fiber_connection_pool'
require 'active_record/connection_adapters/mysql2_adapter'


module ActiveRecord
  module ConnectionHandling

    def mysql2celluloid_connection(config)
      config = config.symbolize_keys

      config[:username] = 'root' if config[:username].nil?
      config[:fiber_pool] ||= 5

      if Mysql2::Client.const_defined? :FOUND_ROWS
        config[:flags] = Mysql2::Client::FOUND_ROWS
      end

      client = ConnectionAdapters::Mysql2celluloidAdapter.pooled_mysql2_client(config)
      options = [config[:host], config[:username], config[:password], config[:database], config[:port], config[:socket], 0]
      ConnectionAdapters::Mysql2celluloidAdapter.new(client, logger, options, config)
    rescue Mysql2::Error => error
      if error.message.include?("Unknown database")
        raise ActiveRecord::NoDatabaseError.new(error.message)
      else
        raise error
      end
    end

  end

  module ConnectionAdapters
    class Mysql2celluloidAdapter < Mysql2Adapter

      class << self

        #  Creates a pooled mysql2 client.
        #
        def pooled_mysql2_client(config)
          client = FiberConnectionPool.new(size: config[:fiber_pool]) do
            client = Mysql2::Client.new(config)
            client.query_options.merge!(as: :array, database_timezone: ActiveRecord::Base.default_timezone)

            configure_connection(config, client)
            
            client
          end

          client.save_data(:last_id) do |connection, method, args|
            connection.last_id
          end

          client.save_data(:affected_rows) do |connection, method, args|
            raise 1 if method == :query_options

            connection.affected_rows rescue nil
          end

          client
        end

        #  Returns true if strict mode sould be utilized for this connection.
        #
        def strict_mode?(config)
          self.type_cast_config_to_boolean(config.fetch(:strict, true))
        end

        #  Configures a provided instance of mysql2 client.
        #
        def configure_connection(config, connection)
          variables = config.fetch(:variables, {}).stringify_keys

          # By default, MySQL 'where id is null' selects the last inserted id.
          # Turn this off. http://dev.rubyonrails.org/ticket/6778
          variables['sql_auto_is_null'] = 0

          # Increase timeout so the server doesn't disconnect us.
          wait_timeout = config[:wait_timeout]
          wait_timeout = 2147483 unless wait_timeout.is_a?(Fixnum)
          variables['wait_timeout'] = self.type_cast_config_to_integer(wait_timeout)

          # Make MySQL reject illegal values rather than truncating or blanking them, see
          # http://dev.mysql.com/doc/refman/5.0/en/server-sql-mode.html#sqlmode_strict_all_tables
          # If the user has provided another value for sql_mode, don't replace it.
          unless variables.has_key?('sql_mode')
            variables['sql_mode'] = strict_mode?(config) ? 'STRICT_ALL_TABLES' : ''
          end

          # NAMES does not have an equals sign, see
          # http://dev.mysql.com/doc/refman/5.0/en/set-statement.html#id944430
          # (trailing comma because variable_assignments will always have content)
          encoding = "NAMES #{config[:encoding]}, " if config[:encoding]

          # Gather up all of the SET variables...
          variable_assignments = variables.map do |k, v|
            if v == ':default' || v == :default
              "@@SESSION.#{k.to_s} = DEFAULT" # Sets the value to the global or compile default
            elsif !v.nil?
              "@@SESSION.#{k.to_s} = #{connection.escape(v.to_s)}"
            end
            # or else nil; compact to clear nils out
          end.compact.join(', ')

          # ...and send them all in one query
          connection.query "SET #{encoding} #{variable_assignments}", async: false
        end

      end

      #  Reserves a connection for the duration of the block.
      #
      def with_reserved_connection(&block)
        @connection.acquire
        yield
      ensure
        @connection.release
      end

      #  Due to concurrent access and FiberConnectionPool specifics, it is a must to
      #  use #gathered_data to store the results (as subsequent calls might be forwarded to a different instance of real connection).
      #
      def last_inserted_id(result)
        @connection.gathered_data[:last_id]
      end

      #  Due to concurrent access and FiberConnectionPool specifics, it is a must to
      #  use #gathered_data to store the results (as subsequent calls might be forwarded to a different instance of real connection).
      #
      def affected_rows
        @connection.gathered_data[:affected_rows]
      end

      #  Re-instantiates the pool.
      #
      def connect
        @connection = self.class.pooled_mysql2_client(@config, metod(:configure_connection))
      end

      # Executes the SQL statement in the context of this connection.
      def execute(sql, name = nil)
        # lol no, won't hit connection pool just for this one
        #
        # if @connection
        #   # make sure we carry over any changes to ActiveRecord::Base.default_timezone that have been
        #   # made since we established the connection
        #   @connection.query_options[:database_timezone] = ActiveRecord::Base.default_timezone
        # end

        log(sql, name) { @connection.query(sql) }
      end

      #  Returns query options of this instance (cached as it is assumed to be the same across all clients)
      #
      def query_options
        @query_options ||= @connection.query_options
      end

      #  Override #quote_string to not hit fiber pool every time we need this method.
      #
      def quote_string(string)
        string.gsub(/\\/, '\&\&').gsub(/'/, "''") 
      end

      #  Patch #exec_delete to fetch affected_rows properly.
      #
      def exec_delete(sql, name, binds)
        execute to_sql(sql, binds), name
        self.affected_rows
      end

      #  Patch #update_sql to fetch affected_rows properly.
      #
      def update_sql(sql, name = nil) #:nodoc:
        super
        self.affected_rows
      end

      #  Noop here, we do everything in class-level method.
      #
      def configure_connection
      end

    end
  end

end
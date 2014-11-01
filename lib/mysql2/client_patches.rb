require "mysql2"
require "celluloid/io"

::Mysql2::Client.class_eval do

  #  Convert socket description (an integer coming from native code) into
  #  a Ruby's IO instance, so that we can await it nicely.
  #
  def io
    @io ||= ::IO.open( socket )
  end

  #  Patch query method to support result awaiting.
  #
  #  Depending on the condition the code runs in, it will do the following:
  #  – When run in a Fiber via Cellulloid, it will resort to Celluloid::IO non-blocking await methods
  #  - Otherwise, it will use Ruby's Kernel.select to block until the data comes in.
  #
  def query_with_celluloid_io(sql, options = {})
    if options[:async] == false
      return query_without_celluloid_io( sql, options )
    end

    query_without_celluloid_io( sql, options.merge(async: true) )
    
    if Celluloid::IO.evented?
      Thread.current[:celluloid_mailbox].reactor.wait_readable( io )
    else
      Kernel.select([ io ])
    end

    #  lol wut? just Rubinius (or mysql2?) bug related to the fact some
    #  obejcts coming from native extensions don't get noticed by GC as still in-use
    #  and are being freed prematurely.
    #
    #  instance variable is perfectly fine here as we anyways cannot send multiple queries
    #  over one connection – we need to wait for a result of each, so no code should come here
    #  and overwrite the previous result until it's consumed (which might happen only under
    #  threaded conditions, which is, again, not supported by this connection)
    #
    @result = async_result    
    @result
  end

  alias_method_chain :query, :celluloid_io

end
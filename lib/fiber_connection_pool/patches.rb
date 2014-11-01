require "fiber_connection_pool"

FiberConnectionPool.class_eval do

  # Return the gathered data for this fiber
  #
  def gathered_data
    @saved_data[Fiber.current] ||= {}
  end

end
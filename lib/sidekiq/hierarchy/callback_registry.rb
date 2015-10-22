require 'mutex_m'

module Sidekiq
  module Hierarchy
    class CallbackRegistry
      include Mutex_m

      def initialize
        @callbacks = {}
        super
      end

      # Thread-safe to prevent clobbering, though this should
      # probably never be called outside initialization anyway.
      # callback is a proc/lambda that implements #call
      def subscribe(event, callback)
        synchronize do
          @callbacks[event] ||= []
          @callbacks[event] << callback
        end
        self
      end

      # Call listeners for a given event one by one.
      # Note that no method signature contracts are enforced.
      def publish(event, *args)
        if to_notify = @callbacks[event]
          to_notify.each { |callback| callback.call(*args) rescue nil }
        end
      end
    end
  end
end

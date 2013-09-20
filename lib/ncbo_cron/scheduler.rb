require 'logger'

# Scheduling/lock gems
require 'redis-lock'
require 'rufus/scheduler'

module NcboCron
  class Scheduler
    ##
    # Schedule a job with redis-supported locking
    # options:
    #   life: length in seconds of the initial lock
    #   job_name: the scheduled job's name
    #   logger: a logger to track errors/debug output
    #   relock_preiod: number of seconds to re-lock for, holds lock during job
    #   redis_host: hostname where redis lock will be performed
    #   redis_port: port for redis host
    #   process: a proc that can be run
    #   minutes_between: how many minutes between job runs (default: 5)
    #   seconds_between: how many seconds between job runs (priority given to minutes if both passed)
    # block: block of code that is the scheduled job
    def self.scheduled_locking_job(options = {}, &block)
      lock_life       = options[:life] || 10*60
      job_name        = options[:job_name] || "ncbo_cron"
      logger          = options[:logger] || Logger.new($stdout)
      relock_period   = options[:relock_period] || 60
      redis_host      = options[:redis_host] || "localhost"
      redis_port      = options[:redis_port] || 6379
      process         = options[:process]
      minutes_between = options[:minutes_between]
      seconds_between = options[:seconds_between]
      scheduler_type  = options[:scheduler_type] || :every
      cron_schedule   = options[:cron_schedule]

      if scheduler_type == :every
        # Minutes/seconds string prep
        interval = "#{seconds_between*1000}" if seconds_between
        interval = "#{minutes_between}m" if minutes_between
        interval = "5m" unless interval
      end
      
      if scheduler_type == :cron
        interval = options[:cron_schedule]
      end

      redis = Redis.new(host: redis_host, port: redis_port)
      scheduler = Rufus::Scheduler.start_new(:thread_name => job_name)

      scheduler.send(scheduler_type, interval, {:allow_overlapping => false}) do
        redis.lock(job_name, life: lock_life) do
          begin
            logger.debug("#{job_name} -- Lock acquired"); logger.flush

            # Spawn a thread to re-acquire the lock every 60 seconds
            thread = Thread.new do
              sleep(relock_period) do
                lock.extend_life(relock_period)
              end
            end
      
            # Make sure thread gets killed if we exit abnormally
            at_exit do
              logger.debug("#{job_name} -- Killing thread"); logger.flush
              Thread.kill(thread)
            end
      
            # Run the process if we have a job
            yield if block_given?
            process.call if process
          ensure
            # Release lock
            logger.debug("#{job_name} -- Killing thread"); logger.flush
            if defined?(thread)
              Thread.kill(thread)
              thread.join
            end
            logger.debug("#{job_name} -- Thread alive? #{defined?(thread) ? thread.alive? : 'false'}"); logger.flush
          end
        end
      end

      # Wait for scheduling (don't exit)
      scheduler.join
    end
  end
end
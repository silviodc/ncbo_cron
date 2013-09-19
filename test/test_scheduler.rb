require 'minitest/unit'
MiniTest::Unit.autorun

require_relative '../lib/ncbo_cron'

class TestScheduler < MiniTest::Unit::TestCase
  def test_scheduler
    begin
      options = {
        job_name: "test_scheduled_job",
        seconds_between: 1
      }
    
      # Spawn a thread with a job that takes a while to finish
      test_array = []
      job1_thread = Thread.new do
        NcboCron::Scheduler.scheduled_locking_job(options) do
          test_array << Time.now
        end
      end
    
      sleep(5)
      finished_array = test_array.dup.freeze
    
      assert_equal 4, finished_array.length
    
      assert job1_thread.alive?
      job1_thread.kill
      job1_thread.join
    ensure
      if defined?(job1_thread) && job1_thread.alive?
        job1_thread.kill
        job1_thread.join
      end
    end
  end

  def test_scheduler_locking
    begin
      options = {
        job_name: "test_scheduled_job_locking",
        seconds_between: 5
      }
      job1 = false
      job2 = false
  
      # Spawn a thread with a job that takes a while to finish
      job1_thread = Thread.new do
        NcboCron::Scheduler.scheduled_locking_job(options) do
          job1 = true
          sleep(30)
        end
      end
  
      # Wait for the lock to be acquired and the job to run
      sleep(10)
  
      # Spawn a second thread with the same name. This one shouldn't
      # be able to get a lock because of the long-running job above.
      job2_thread = Thread.new do
        NcboCron::Scheduler.scheduled_locking_job(options.merge(seconds_between: 1)) do
          job2 = true
        end
      end
  
      sleep(10)
  
      assert job1_thread.alive?
      assert job2_thread.alive?
      assert job1
      refute job2
    ensure
      if defined?(job1_thread)
        job1_thread.kill
        job1_thread.join
      end
      if defined?(job2_thread)
        job2_thread.kill
        job2_thread.join
      end
    end
   end
end
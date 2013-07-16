
#
# Specifying rufus-scheduler
#
# Wed Apr 17 06:00:59 JST 2013
#

require 'spec_helper'


describe Rufus::Scheduler do

  describe '#initialize' do

    it 'starts the scheduler thread' do

      scheduler = Rufus::Scheduler.new

      t = Thread.list.find { |t|
        t[:name] == "rufus_scheduler_#{scheduler.object_id}_scheduler"
      }

      t[:rufus_scheduler].should == scheduler
    end

    it 'sets a :rufus_scheduler thread local var' do

      scheduler = Rufus::Scheduler.new
    end

    it 'accepts a :frequency option' do

      scheduler = Rufus::Scheduler.new(:frequency => 2)

      scheduler.frequency.should == 2
    end

    it 'accepts a :thread_name option' do

      scheduler = Rufus::Scheduler.new(:thread_name => 'oliphant')

      t = Thread.list.find { |t| t[:name] == 'oliphant' }

      t[:rufus_scheduler].should == scheduler
    end
  end

  context 'instance methods' do

    before :each do
      @scheduler = Rufus::Scheduler.new
    end
    after :each do
      @scheduler.shutdown
    end

    describe '#unschedule(job_or_job_id)' do

      it 'works'
      it 'carefully unschedules repeat jobs'
    end

    describe '#uptime' do

      it 'returns the uptime as a float' do

        @scheduler.uptime.should > 0.0
      end
    end

    describe '#uptime_s' do

      it 'returns the uptime as a human readable string' do

        sleep 1

        @scheduler.uptime_s.should match(/^[12]s\d+$/)
      end
    end

    describe '#join' do

      it 'joins the scheduler thread' do

        t = Thread.new { @scheduler.join; Thread.current['a'] = 'over' }

        t['a'].should == nil

        @scheduler.shutdown

        sleep(1)

        t['a'].should == 'over'
      end
    end

    describe '#job(job_id)' do

      it 'returns nil if there is no corresponding Job instance' do

        @scheduler.job('nada').should == nil
      end

      it 'returns the corresponding Job instance' do

        job_id = @scheduler.in '10d' do; end

        sleep(1) # give it some time to get scheduled

        @scheduler.job(job_id).job_id.should == job_id
      end
    end

    describe '#job_threads' do

      it 'returns [] when there are no jobs running' do

        @scheduler.job_threads.should == []
      end

      it 'returns the list of threads of the running jobs' do

        job =
          @scheduler.schedule_in('0s') do
            sleep(1)
          end

        sleep 0.4

        @scheduler.job_threads.size.should == 1

        t = @scheduler.job_threads.first

        t.class.should == Thread
        t[@scheduler.thread_key][:job].should == job
      end

      it 'does not return threads from other schedulers' do

        scheduler = Rufus::Scheduler.new

        job =
          @scheduler.schedule_in('0s') do
            sleep(1)
          end

        sleep 0.4

        scheduler.job_threads.should == []

        scheduler.shutdown
      end
    end

    describe '#running_jobs' do

      it 'returns [] when there are no running jobs' do

        @scheduler.running_jobs.should == []
      end

      it 'returns a list of running Job instances' do

        job =
          @scheduler.schedule_in('0s') do
            sleep(1)
          end

        sleep 0.4

        job.running?.should == true
        @scheduler.running_jobs.should == [ job ]
      end

      it 'does not return twice the same job' do

        job =
          @scheduler.schedule_every('0.3s') do
            sleep(5)
          end

        sleep 1.5

        job.running?.should == true
        @scheduler.running_jobs.should == [ job ]
      end
    end

    #--
    # management methods
    #++

    describe '#terminate_all_jobs' do

      it 'unschedules all the jobs' do

        @scheduler.in '10d' do; end
        @scheduler.at Time.now + 10_000 do; end

        sleep 0.4

        @scheduler.jobs.size.should == 2

        @scheduler.terminate_all_jobs

        @scheduler.jobs.size.should == 0
      end

      it 'blocks until all the running jobs are done' do

        counter = 0

        @scheduler.in '0s' do
          sleep 1
          counter = counter + 1
        end

        sleep 0.4

        @scheduler.terminate_all_jobs

        @scheduler.jobs.size.should == 0
        @scheduler.running_jobs.size.should == 0
        counter.should == 1
      end
    end

    describe '#shutdown' do

      it 'blanks the uptime' do

        @scheduler.shutdown

        @scheduler.uptime.should == nil
      end

      it 'shuts the scheduler down' do

        @scheduler.shutdown

        sleep 0.100
        sleep 0.400 if RUBY_VERSION < '1.9.0'

        t = Thread.list.find { |t|
          t[:name] == "rufus_scheduler_#{@scheduler.object_id}"
        }

        t.should == nil
      end

      it 'has a #stop alias' do

        @scheduler.stop

        @scheduler.uptime.should == nil
      end

      #it 'has a #close alias'
    end

    describe '#shutdown(:terminate)' do

      it 'shuts down when all the jobs terminated' do

        counter = 0

        @scheduler.in '0s' do
          sleep 1
          counter = counter + 1
        end

        sleep 0.4

        @scheduler.shutdown(:terminate)

        counter.should == 1
        @scheduler.uptime.should == nil
        @scheduler.running_jobs.should == []
      end
    end

    describe '#shutdown(:kill)' do

      it 'kills all the jobs and then shuts down' do

        counter = 0

        @scheduler.in '0s' do
          sleep 1
          counter = counter + 1
        end
        @scheduler.at Time.now + 0.3 do
          sleep 1
          counter = counter + 1
        end

        sleep 0.4

        @scheduler.shutdown(:kill)

        sleep 1.4

        counter.should == 0
        @scheduler.uptime.should == nil
        @scheduler.running_jobs.should == []
      end
    end

    describe '#pause' do

      it 'pauses the scheduler' do

        job = @scheduler.schedule_in '1s' do; end

        @scheduler.pause

        sleep(3)

        job.last_time.should == nil
      end
    end

    describe '#resume' do

      it 'works' do

        job = @scheduler.schedule_in '2s' do; end

        @scheduler.pause
        sleep(1)
        @scheduler.resume
        sleep(2)

        job.last_time.should_not == nil
      end
    end

    describe '#paused?' do

      it 'returns true if the scheduler is paused' do

        @scheduler.pause
        @scheduler.paused?.should == true
      end

      it 'returns false if the scheduler is not paused' do

        @scheduler.paused?.should == false

        @scheduler.pause
        @scheduler.resume

        @scheduler.paused?.should == false
      end
    end

    #--
    # job methods
    #++

    describe '#jobs' do

      it 'is empty at the beginning' do

        @scheduler.jobs.should == []
      end

      it 'returns the list of scheduled jobs' do

        @scheduler.in '10d' do; end
        @scheduler.in '1w' do; end

        sleep(1)

        jobs = @scheduler.jobs

        jobs.collect { |j| j.original }.sort.should == %w[ 10d 1w ]
      end

      it 'returns all the jobs (even those pending reschedule)' do

        @scheduler.in '0s', :blocking => true do
          sleep 2
        end

        sleep 0.4

        @scheduler.jobs.size.should == 1
      end

      it 'does not return unscheduled jobs' do

        job =
          @scheduler.schedule_in '0s', :blocking => true do
            sleep 2
          end

        sleep 0.4

        job.unschedule

        @scheduler.jobs.size.should == 0
      end
    end

    describe '#every_jobs' do

      it 'returns EveryJob instances' do

        @scheduler.at '2030/12/12 12:10:00' do; end
        @scheduler.in '10d' do; end
        @scheduler.every '5m' do; end

        sleep(1)

        jobs = @scheduler.every_jobs

        jobs.collect { |j| j.original }.sort.should == %w[ 5m ]
      end
    end

    describe '#at_jobs' do

      it 'returns AtJob instances' do

        @scheduler.at '2030/12/12 12:10:00' do; end
        @scheduler.in '10d' do; end
        @scheduler.every '5m' do; end

        sleep(1)

        jobs = @scheduler.at_jobs

        jobs.collect { |j| j.original }.sort.should == [ '2030/12/12 12:10:00' ]
      end
    end

    describe '#in_jobs' do

      it 'returns InJob instances' do

        @scheduler.at '2030/12/12 12:10:00' do; end
        @scheduler.in '10d' do; end
        @scheduler.every '5m' do; end

        sleep(1)

        jobs = @scheduler.in_jobs

        jobs.collect { |j| j.original }.sort.should == %w[ 10d ]
      end
    end

    describe '#cron_jobs' do

      it 'returns CronJob instances'
    end
  end
end


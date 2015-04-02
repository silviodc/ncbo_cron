require 'ostruct'

module NcboCron
  extend self
  attr_reader :settings

  @settings = OpenStruct.new
  @settings_run = false
  def config(&block)
    return if @settings_run
    @settings_run = true

    # Redis is used for two separate things in ncbo_cron:
    # 1) locating the queue for the submissions to be processed and
    # 2) managing the processing lock.
    @settings.redis_host ||= "localhost"
    @settings.redis_port ||= 6379
    puts "(CR) >> Using Redis instance at #{@settings.redis_host}:#{@settings.redis_port}"

    # Daemon
    @settings.daemonize ||= true
    # REPL for working with scheduler
    @settings.console ||= false
    # submission id to add to the queue
    @settings.queue_submission ||= nil
    # view queued jobs
    @settings.view_queue ||= false
    @settings.enable_processing ||= true
    @settings.enable_pull ||= true
    @settings.enable_flush ||= true
    @settings.enable_warmq ||= true
    # enable ontology analytics
    @settings.enable_ontology_analytics ||= true
    # enable ontologies report
    @settings.enable_ontologies_report ||= true
    # UMLS auto-pull
    @settings.pull_umls_url ||= ""
    @settings.enable_pull_umls ||= false

    # Schedulues
    @settings.cron_schedule ||= "30 */4 * * *"
    # Pull schedule
    @settings.pull_schedule ||= "00 18 * * *"
    # Delete class graphs of archive submissions
    @settings.cron_flush ||= "00 22 * * 2"
    # Warmup long time running queries
    @settings.cron_warmq ||= "00 */3 * * *"
    # Ontology analytics refresh schedule
    # 15 0 * * 1 - run once a week on Monday at 12:15AM
    @settings.cron_ontology_analytics ||= "15 0 * * 1"
    # Ontologies report generation schedule
    # 30 1 * * * - run daily at 1:30AM
    @settings.cron_ontologies_report ||= "30 1 * * *"
    # Ontologies Report file location
    @settings.ontology_report_path = "../../reports/ontologies_report.json"

    @settings.log_level ||= :info
    unless (@settings.log_path && File.exists?(@settings.log_path))
      log_dir = File.expand_path("../../../logs", __FILE__)
      FileUtils.mkdir_p(log_dir)
      @settings.log_path = "#{log_dir}/scheduler.log"
    end
    if File.exists?("/var/run/ncbo_cron")
      pid_path = File.expand_path("/var/run/ncbo_cron/ncbo_cron.pid", __FILE__)
    else
      pid_path = File.expand_path("../../../ncbo_cron.pid", __FILE__)
    end
    @settings.pid_path ||= pid_path

    # minutes between process queue checks (override seconds)
    @settings.minutes_between ||= 5
    # seconds between process queue checks
    @settings.seconds_between ||= nil

    # Override defaults
    yield @settings if block_given?
  end
end

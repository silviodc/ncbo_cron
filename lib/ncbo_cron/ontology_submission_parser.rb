module NcboCron
  module Models

    class OntologySubmissionParser

      QUEUE_HOLDER = "parseQueue"
      IDPREFIX = "sub:"

      ACTION_DELIM = "|"
      ACTIONS = [:all, :index, :metrics]

      def initialize()
      end

      def queue_submission(submission, actions=[:all])
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        actionStr = ""
        i = 1

        actions.each do |action|
          if (ACTIONS.include?(action))
            actionStr << action.to_s

            if i < actions.length
              actionStr << ACTION_DELIM
            end
          end
          i += 1
        end
        redis.hset(QUEUE_HOLDER, get_prefixed_id(submission.id), actionStr)
      end

      def parse_submissions
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        all = redis.hgetall(QUEUE_HOLDER)
        prefix_remove = Regexp.new(/^#{IDPREFIX}/)

        all.each do |key, val|
          realKey = key.sub prefix_remove, ''
          valArr = val.split(ACTION_DELIM).sort
          redis.hdel(QUEUE_HOLDER, key)
          parse_submission(realKey, valArr)
        end
      end

      def get_prefixed_id(id)
        return "#{IDPREFIX}#{id}"
      end

      private

      def parse_submission(submissionId, actions)
        logger = Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        sub = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submissionId)).first

        if sub
          process_rdf = false
          index_search = false
          run_metrics = false
          all = false

          actions.each do |action|
            case action
              when "all"
                process_rdf = true
                index_search = true
                run_metrics = true
                all = true
              when "index"
                index_search = true
              when "metrics"
                run_metrics = true
            end
            break if all
          end
          sub.process_submission(logger, process_rdf, index_search, run_metrics)
        end
      end

    end
  end
end

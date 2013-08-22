module NcboCron
  module Models

    class OntologySubmissionParser

      QUEUE_HOLDER = "parseQueue"
      IDPREFIX = "sub:"

      ACTION_DELIM = "|"
      ACTIONS = ["all", "index", "metrics"]

      def initialize()
      end

      def queue_submission(submission, actions=["all"])
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        actionStr = ""
        i = 1

        actions.each do |action|
          if (ACTIONS.include?(action))
            actionStr << action

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
          valArr = val.split(ACTION_DELIM)
          redis.hdel(QUEUE_HOLDER, key)
          parse_submission(realKey, valArr)
        end
      end

      def get_prefixed_id(id)
        return "#{IDPREFIX}#{id}"
      end

      private

      def parse_submission(submissionId, actions)
        sub = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submissionId)).first

        actions.each do |action|
          case action
            when "all"
              puts "It's all"
            when "index"
              puts "It's index"
            when "metrics"
              puts "It's metrix"
          end
        end


      end

    end
  end
end

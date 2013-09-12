module NcboCron
  module Models

    class OntologySubmissionParser

      QUEUE_HOLDER = "parseQueue"
      IDPREFIX = "sub:"

      ACTION_DELIM = "|"
      ACTIONS = [:all, :index_search, :run_metrics, :process_annotator]

      def initialize()
      end

      def queue_submission(submission, actions=[:all])
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        actionStr = ""
        i = 1

        actions.each do |action|
          if (ACTIONS.include?(action))
            act = action.to_s

            if (act == "all")
              actionStr = act
              break
            else
              actionStr << act
              actionStr << ACTION_DELIM if i < actions.length
            end
          end
          i += 1
        end
        redis.hset(QUEUE_HOLDER, get_prefixed_id(submission.id), actionStr) unless actionStr.empty?
      end

      def process_queue_submissions
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        all = redis.hgetall(QUEUE_HOLDER)
        prefix_remove = Regexp.new(/^#{IDPREFIX}/)

        all.each do |key, val|
          valArr = val.split(ACTION_DELIM)

          if valArr.include?("all")
            valArr = ACTIONS.dup
          end
          actions = Hash[valArr.map {|v| [v, true]}]
          realKey = key.sub prefix_remove, ''
          redis.hdel(QUEUE_HOLDER, key)
          process_queue_submission(realKey, actions)
        end
      end

      def get_prefixed_id(id)
        return "#{IDPREFIX}#{id}"
      end

      private

      def process_queue_submission(submissionId, actions={})
        logger = Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        sub = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submissionId)).first

        if sub
          sub.process_submission(logger, actions)

          if (actions[:process_annotator])
            sub.bring(:ontology) if sub.bring?(:ontology)
            to_bring = [:acronym, :submissionId].select {|x| sub.bring?(x)}
            sub.ontology.bring(to_bring) if to_bring.length > 0
            parsed = sub.ready?(status: [:rdf, :rdf_labels])

            raise Exception, "Annotator entries cannot be generated on the submission #{sub.ontology.acronym}/submissions/#{sub.submissionId} because it has not been successfully parsed" unless parsed
            status = LinkedData::Models::SubmissionStatus.find("ANNOTATOR").first
            #remove ANNOTATOR status before starting
            sub.remove_submission_status(status)

            begin
              annotator = Annotator::Models::NcboAnnotator.new
              annotator.create_cache_for_submission(logger, self)
              annotator.generate_dictionary_file()
              sub.add_submission_status(status)
            rescue Exception => e
              sub.add_submission_status(status.get_error_status)
              logger.info(e.message)
              logger.flush
            end
            sub.save()
          end
        end
      end

    end
  end
end

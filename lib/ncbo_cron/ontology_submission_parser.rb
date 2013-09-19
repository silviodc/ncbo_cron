require 'multi_json'

module NcboCron
  module Models

    class OntologySubmissionParser

      QUEUE_HOLDER = "parseQueue"
      IDPREFIX = "sub:"

      ACTIONS = {
        :process_rdf => true,
        :index_search => true,
        :run_metrics => true,
        :process_annotator => true
      }

      def initialize()
      end

      def queue_submission(submission, actions={:all => true})
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)

        if (actions[:all])
          actions = ACTIONS.dup
        else
          actions.delete_if {|k, v| !ACTIONS.has_key?(k)}
        end
        actionStr = MultiJson.dump(actions)
        redis.hset(QUEUE_HOLDER, get_prefixed_id(submission.id), actionStr) unless actions.empty?
      end

      def process_queue_submissions()
        redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
        all = queued_items(redis)

        all.each do |process_data|
          actions = process_data[:actions]
          realKey = process_data[:key]
          key = process_data[:redis_key]
          redis.hdel(QUEUE_HOLDER, key)
          process_queue_submission(realKey, actions)
        end
      end
      
      def queued_items(redis)
        all = redis.hgetall(QUEUE_HOLDER)
        prefix_remove = Regexp.new(/^#{IDPREFIX}/)
        items = []
        all.each do |key, val|
          items << {
            key: key.sub(prefix_remove, ''),
            redis_key: key,
            actions: MultiJson.load(val, symbolize_keys: true)
          }
        end
        items
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
          process_annotator(logger, sub) if actions[:process_annotator]
        end
      end

      def process_annotator(logger, sub)
        to_bring = [:ontology, :submissionId].select {|x| sub.bring?(x)}
        sub.bring(to_bring) if to_bring.length > 0
        sub.ontology.bring(:acronym) if sub.ontology.bring?(:acronym)
        parsed = sub.ready?(status: [:rdf, :rdf_labels])

        raise Exception, "Annotator entries cannot be generated on the submission #{sub.ontology.acronym}/submissions/#{sub.submissionId} because it has not been successfully parsed" unless parsed
        status = LinkedData::Models::SubmissionStatus.find("ANNOTATOR").first
        #remove ANNOTATOR status before starting
        sub.remove_submission_status(status)

        begin
          annotator = Annotator::Models::NcboAnnotator.new
          annotator.create_cache_for_submission(logger, sub)
          annotator.generate_dictionary_file()
          sub.add_submission_status(status)
        rescue Exception => e
          sub.add_submission_status(status.get_error_status())
          logger.info(e.message)
          logger.flush()
        end
        sub.save()
      end

    end
  end
end

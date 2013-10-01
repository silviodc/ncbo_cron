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
        redis = Redis.new(:host => $QUEUE_REDIS_HOST, :port => $QUEUE_REDIS_PORT)

        if (actions[:all])
          actions = ACTIONS.dup
        else
          actions.delete_if {|k, v| !ACTIONS.has_key?(k)}
        end
        actionStr = MultiJson.dump(actions)
        redis.hset(QUEUE_HOLDER, get_prefixed_id(submission.id), actionStr) unless actions.empty?
      end

      def process_queue_submissions(options = {})
        logger = options[:logger] || Logger.new($stdout)
        logger ||= Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        redis = Redis.new(:host => $QUEUE_REDIS_HOST, :port => $QUEUE_REDIS_PORT)
        all = queued_items(redis, logger)

        all.each do |process_data|
          actions = process_data[:actions]
          realKey = process_data[:key]
          key = process_data[:redis_key]
          redis.hdel(QUEUE_HOLDER, key)
          begin
            process_queue_submission(logger, realKey, actions)
          rescue Exception => e
            logger.debug "Exception processing #{realKey}"
            logger.error e.message
            logger.error e.backtrace.join("\n\t")
          end
        end
      end
      
      def queued_items(redis, logger=nil)
        logger ||= Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        all = redis.hgetall(QUEUE_HOLDER)
        prefix_remove = Regexp.new(/^#{IDPREFIX}/)
        items = []
        all.each do |key, val|
          begin
            actions = MultiJson.load(val, symbolize_keys: true)
          rescue Exception => e
            logger.error("Invalid record in the parse queue: #{key} - #{val}:\n")
            logger.error(e.message + "\n" + e.backtrace.join("\n\t"))
            logger.flush()
            next
          end
          items << {
            key: key.sub(prefix_remove, ''),
            redis_key: key,
            actions: actions
          }
        end
        items
      end

      def get_prefixed_id(id)
        return "#{IDPREFIX}#{id}"
      end

      private

      def process_queue_submission(logger, submissionId, actions={})
        sub = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submissionId)).first
        
        sub.bring(:uploadFilePath)
        logger = Logger.new("#{sub.uploadFilePath}_parsing.log", "a")
        logger.debug "Starting parsing for #{submissionId}\n\n\n\n"

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

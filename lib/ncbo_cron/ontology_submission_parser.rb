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
        :process_annotator => true,
        :diff => true
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
        logger = options[:logger]
        logger ||= Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        redis = Redis.new(:host => $QUEUE_REDIS_HOST, :port => $QUEUE_REDIS_PORT)
        all = queued_items(redis, logger)

        all.each do |process_data|
          actions = process_data[:actions]
          realKey = process_data[:key]
          key = process_data[:redis_key]
          redis.hdel(QUEUE_HOLDER, key)
          begin
            logger.info "Starting parsing for #{realKey}"
            process_queue_submission(logger, realKey, actions)
            logger.info "Finished parsing for #{realKey}"
          rescue Exception => e
            logger.debug "Exception processing #{realKey}"
            logger.error(e.message + "\n" + e.backtrace.join("\n\t"))
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

      def zombie_classes_graphs
        query = "SELECT DISTINCT ?g WHERE { GRAPH ?g { ?s ?p ?o }}"
        class_graphs = []
        Goo.sparql_query_client.query(query).each_solution do |sol|
          if sol[:g].to_s["/submissions/"] && sol[:g].to_s["/ontologies/"]
            class_graphs << sol[:g].to_s
          end
        end
        onts_set = Set.new
        onts = LinkedData::Models::Ontology.where.include(:acronym,:summaryOnly).all.each do |o|
          onts_set << o.id.to_s
        end
        zombies = []
        class_graphs.each do |g|
          zombies << g unless onts_set.include?(g.split("/")[0..-3].join("/"))
        end
        return zombies
      end

      def process_flush_classes(logger)
        onts = LinkedData::Models::Ontology.where.include(:acronym,:summaryOnly).all
        status_archived = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
        deleted = []
        onts = onts.sort_by { |x| x.acronym }
        onts.each do |ont|
          if !ont.summaryOnly
            logger.info("Checking graphs to delete for #{ont.id.to_s}")
            submissions = LinkedData::Models::OntologySubmission.where(ontology: ont)
                            .include(:submissionId)
                            .include(:submissionStatus)
                            .all
            submissions = submissions.sort_by { |x| x.submissionId }.reverse[0..10]
            last_ready = ont.latest_submission(status: :ready)
            next if last_ready.nil?
            submissions.each do |sub|
              if LinkedData::Models::Class.where.in(sub).count > 1
                if sub.archived?
                  logger.info "Deleting graph #{sub.id.to_s} ..." ; logger.flush
                  t0 = Time.now
                  sub.delete_classes_graph
                  logger.info "Graph #{sub.id.to_s} deleted in #{Time.now-t0} sec."; logger.flush
                  deleted << sub
                else
                  if sub.id.to_s != last_ready.id.to_s
                    sub.bring_remaining
                    logger.info "DELETE #{sub.id.to_s}"; logger.flush
                    sub.delete_classes_graph
                    logger.info "DELETE setting to archive #{sub.id.to_s}"; logger.flush
                    sub.add_submission_status(status_archived)
                    sub.save
                    logger.info "DELETE DONE"; logger.flush
                  end
                end
              end
            end
          end
        end

        zombie_classes_graphs.each do |zg|
          logger.info("Zombie class graph #{zg}") ; logger.flush
        end

        logger.info("finish process_flush_classes") ; logger.flush

        return deleted
      end


      private

      def process_queue_submission(logger, submissionId, actions={})
        sub = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(submissionId)).first

        sub.bring_remaining; sub.ontology.bring(:acronym)
        log_path = "#{sub.uploadFilePath}_parsing.log"
        logger.info "Logging parsing output to #{log_path}"
        logger = Logger.new(log_path)
        logger.debug "Starting parsing for #{submissionId}\n\n\n\n"

        status_archived = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first

        if sub
          # Check to make sure the file has been downloaded
          if sub.pullLocation && (!sub.uploadFilePath || !File.exist?(sub.uploadFilePath))
            file, filename = sub.download_ontology_file
            file_location = sub.class.copy_file_repository(sub.ontology.acronym, sub.submissionId, file, filename)
            file_location = "../" + file_location if file_location.start_with?(".") # relative path fix
            sub.uploadFilePath = File.expand_path(file_location, __FILE__)
            sub.save
          end

          sub.process_submission(logger, actions)
          if sub.ready?
            submissions = LinkedData::Models::OntologySubmission
              .where(ontology: sub.ontology)
              .include(:submissionId)
              .include(:submissionStatus)
              .all
            # Get recent submissions, sorted by submissionId (latest first)
            recent_submissions = submissions.sort { |a,b| b.submissionId <=> a.submissionId }[0..10]
            # Mark older submissions archived
            recent_submissions.each do |old_sub|
              next if old_sub.id.to_s == sub.id.to_s
              next if sub.submissionId < old_sub.submissionId
              unless sub.archived?
                old_sub.bring_remaining
                old_sub.add_submission_status(status_archived)
                old_sub.save
              end
            end
          end

          process_annotator(logger, sub) if actions[:process_annotator]

          # Update the most recent 5 submissions with ontology diffs
          submissions = LinkedData::Models::OntologySubmission
            .where(ontology: sub.ontology)
            .include(:submissionId)
            .include(:diffFilePath)
            .all
          # Get recent submissions, sorted by submissionId (latest first)
          recent_submissions = submissions.sort { |a,b| b.submissionId <=> a.submissionId }[0..5]
          recent_submissions.each_with_index do |this_sub, i|
            if this_sub.diffFilePath.nil?
              begin
                # Get the next submission, should be an older version.
                that_sub = recent_submissions[i+1]
                this_sub.diff(logger, that_sub) unless that_sub.nil?
              rescue
                next
              end
            end
          end
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
          logger.error(e.message + "\n" + e.backtrace.join("\n\t"))
          logger.flush()
        end
        sub.save()
      end

    end
  end
end

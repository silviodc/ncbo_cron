require 'open-uri'
require 'logger'
require_relative 'ontology_submission_parser'

module NcboCron
  module Models

    class OntologyPull

      def initialize()
      end

      def do_remote_ontology_pull(options = {})
        logger = options[:logger] || Logger.new($stdout)
        ontologies = LinkedData::Models::Ontology.where.include(:acronym).all

        ontologies.each do |ont|
          begin
            last = ont.latest_submission(status: [:uploaded])
            next if last.nil?
            last.bring(:pullLocation) if last.bring?(:pullLocation)
            last.bring(:uploadFilePath) if last.bring?(:uploadFilePath)

            if (last.remote_file_exists?(last.pullLocation.to_s) && File.exist?(last.uploadFilePath))
              logger.info "Checking download for #{ont.acronym}"
              logger.info "Location: #{last.pullLocation.to_s}"; logger.flush
              file, filename = last.download_ontology_file()
              file.open
              remote_contents  = file.read
              file_contents = open(last.uploadFilePath) { |f| f.read }
              md5remote = Digest::MD5.hexdigest(remote_contents)
              md5local = Digest::MD5.hexdigest(file_contents)

              unless (md5remote.eql?(md5local))
                logger.info "New file found for #{ont.acronym}\nold: #{md5local}\nnew: #{md5remote}"
                logger.flush()
                create_submission(ont, last, file, filename, logger)
              end
            end
          rescue Exception => e
            logger.error "Problem retrieving #{ont.acronym} in OntologyPull:\n" + e.message + "\n" + e.backtrace.join("\n\t")
            logger.flush()
            next
          end
        end
      end

      def create_submission(ont, sub, file, filename, logger=nil)
        logger ||= Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        new_sub = LinkedData::Models::OntologySubmission.new

        sub.bring_remaining
        sub.loaded_attributes.each do |attr|
          new_sub.send("#{attr}=", sub.send(attr))
        end

        submission_id = ont.next_submission_id()
        new_sub.submissionId = submission_id
        file_location = LinkedData::Models::OntologySubmission.copy_file_repository(ont.acronym, submission_id, file, filename)
        new_sub.uploadFilePath = file_location
        new_sub.submissionStatus = nil
        new_sub.creationDate = nil
        new_sub.released = DateTime.now
        new_sub.missingImports = nil
        new_sub.metrics = nil

        if new_sub.valid?
          new_sub.save()
          submission_queue = NcboCron::Models::OntologySubmissionParser.new
          submission_queue.queue_submission(new_sub, {all: true})
          logger.info("OntologyPull created a new submission (#{submission_id}) for ontology #{ont.acronym}")
        else
          logger.error("Unable to create a new submission in OntologyPull: #{new_sub.errors}")
          logger.flush()
        end
      end
    end
  end
end



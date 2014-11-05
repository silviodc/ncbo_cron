require 'open-uri'
require 'logger'
require_relative 'ontology_submission_parser'

module NcboCron
  module Models

    class OntologyPull

      class RemoteFileException < StandardError
      end

      def initialize()
      end

      def do_remote_ontology_pull(options = {})
        logger = options[:logger] || Logger.new($stdout)
        logger.info "UMLS auto-pull #{options[:enable_pull_umls] == true}"
        logger.flush
        ontologies = LinkedData::Models::Ontology.where.include(:acronym).all
        enable_pull_umls = options[:enable_pull_umls]
        umls_download_url = options[:pull_umls_url]

        ontologies.sort! {|a,b| a.acronym.downcase <=> b.acronym.downcase}

        new_submissions = []
        ontologies.each do |ont|
          begin
            last = ont.latest_submission(status: :any)
            next if last.nil?
            last.bring(:hasOntologyLanguage) if last.bring?(:hasOntologyLanguage)
            if !enable_pull_umls && last.hasOntologyLanguage.umls?
              next
            end
            last.bring(:pullLocation) if last.bring?(:pullLocation)
            next if last.pullLocation.nil?
            last.bring(:uploadFilePath) if last.bring?(:uploadFilePath)

            if (last.hasOntologyLanguage.umls? && umls_download_url)
              last.pullLocation= RDF::URI.new(umls_download_url + last.pullLocation.split("/")[-1])
              logger.info("Using alternative download for umls #{last.pullLocation.to_s}")
              logger.flush
            end
            if (last.remote_file_exists?(last.pullLocation.to_s))
              logger.info "Checking download for #{ont.acronym}"
              logger.info "Location: #{last.pullLocation.to_s}"; logger.flush
              file, filename = last.download_ontology_file()
              file.open
              remote_contents  = file.read
              if last.uploadFilePath && File.exist?(last.uploadFilePath)
                file_contents = open(last.uploadFilePath) { |f| f.read }
                md5remote = Digest::MD5.hexdigest(remote_contents)
                md5local = Digest::MD5.hexdigest(file_contents)
                new_file_exists = (not md5remote.eql?(md5local))
              else
                # There is no existing file, so let's create a submission with the downloaded one
                new_file_exists = true
              end

              if new_file_exists
                logger.info "New file found for #{ont.acronym}\nold: #{md5local}\nnew: #{md5remote}"
                logger.flush()
                new_submissions << create_submission(ont, last, file, filename, logger)
              end
            else
              begin
                raise RemoteFileException
              rescue RemoteFileException
                logger.info "RemoteFileException: No submission file at pull location #{last.pullLocation.to_s} for ontology #{ont.acronym}."
                logger.flush
                LinkedData::Utils::Notifications.remote_ontology_pull(last)
              end
            end
          rescue Exception => e
            logger.error "Problem retrieving #{ont.acronym} in OntologyPull:\n" + e.message + "\n" + e.backtrace.join("\n\t")
            logger.flush()
            next
          end
        end
        new_submissions
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

        new_sub
      end
    end
  end
end



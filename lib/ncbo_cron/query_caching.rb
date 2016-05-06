
module NcboCron
  module Models
    class QueryWarmer
      def initialize(logger)
        @logger = logger
      end

      def run
        iterations = 0
        page = 1
        size = 100
        retrieve_latest_submissions.each do |acr, sub|
          # next unless ["CCO", "OBIWS", "AURA"].include?(acr)
          @logger.info("running first page mappings #{sub.id.to_s}")
          @logger.flush()
          mappings = LinkedData::Mappings.mappings_ontologies(sub, nil, page, size, nil, reload_cache=true)
          @logger.info("done #{mappings.length}")
          @logger.info("running first page classes #{sub.id.to_s}")
          @logger.flush()
          paging = LinkedData::Models::Class.in(sub).page(page, size)
          cls_count = sub.class_count(@logger)
          # prevent a COUNT SPARQL query if possible
          paging.page_count_set(cls_count) if cls_count > -1
          clss = paging.page(page, size).all
          @logger.info("done #{clss.length}")
          @logger.flush()
          iterations += 1
        end
        iterations
      end

      def retrieve_latest_submissions(options = {})
        status = (options[:status] || "RDF").to_s.upcase
        include_ready = status.eql?("READY") ? true : false
        status = "RDF" if status.eql?("READY")
        any = true if status.eql?("ANY")
        include_views = options[:include_views] || false

        if any
          submissions_query = LinkedData::Models::OntologySubmission.where
        else
          submissions_query = LinkedData::Models::OntologySubmission.where(submissionStatus: [code: status])
        end

        submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
        submissions = submissions_query.include(:submissionStatus, :submissionId, ontology: [:acronym]).to_a
        latest_submissions = {}

        submissions.each do |sub|
          next if include_ready && !sub.ready?
          latest_submissions[sub.ontology.acronym] ||= sub
          latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
        end
        latest_submissions
      end

    end
  end
end

# require 'ontologies_linked_data'
# require 'goo'
# require 'ncbo_annotator'
# require 'ncbo_cron/config'
# require_relative '../../config/config'
#
# query_warmer_path = File.join("logs", "warmq.log")
# query_warmer_logger = Logger.new(query_warmer_path)
# NcboCron::Models::QueryWarmer.new(query_warmer_logger).run
# ./bin/ncbo_cron --disable-processing true --disable-pull true --disable-flush true --disable-ontology-analytics true --disable-mapping-counts true --disable-ontologies-report true --warm-long-queries '14 * * * *'
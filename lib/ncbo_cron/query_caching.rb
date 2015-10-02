
module NcboCron
  module Models
    class QueryWarmer
      def initialize(logger)
        @logger = logger
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
          submissions_query = LinkedData::Models::OntologySubmission
                                .where(submissionStatus: [ code: status])
        end

        submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
        submissions = submissions_query.
            include(:submissionStatus,:submissionId, ontology: [:acronym]).to_a

        latest_submissions = {}
        submissions.each do |sub|
          next if include_ready && !sub.ready?
          latest_submissions[sub.ontology.acronym] ||= sub
          latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
        end
        return latest_submissions
      end

      def run
        iterations = 0
        retrieve_latest_submissions.each do |acr,sub|
          @logger.info("running first page mappings #{sub.id.to_s}")
          @logger.flush()
          mappings = LinkedData::Mappings
                    .mappings_ontologies(sub,nil,1,100,nil,reload_cache=true)
          @logger.info("done #{mappings.length}")
          @logger.info("running first page classes #{sub.id.to_s}")
          @logger.flush()
          clss = LinkedData::Models::Class.where.in(sub).page(1,100).all
          @logger.info("done #{clss.length}")
          @logger.flush()
          iterations += 1
        end
        return iterations
      end
    end
  end
end

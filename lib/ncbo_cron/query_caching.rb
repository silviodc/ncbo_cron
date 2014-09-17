
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
        @logger.info("running counts per ontology")
        @logger.flush()
        new_counts = LinkedData::Mappings.mapping_counts(
                                            enable_debug=true,logger=@logger,
                                            reload_cache=true)
        persistent_counts = {}
        LinkedData::Models::MappingCount.where(pair_count: false)
        .include(:all)
        .all
        .each do |m|
          persistent_counts[m.ontologies.first] = m
        end
        
        new_counts.each do |acr|
          new_count = counts[acr]
          if persistent_counts.include?(acr)
            inst = model_count[acr]
            if new_count != inst.count
              inst.count = new_count
              inst.save
            end
          else
            m = LinkedData::Models::MappingCount.new
            m.ontologies = [acr]
            m.pair_count = false
            m.count = new_count
            m.save
          end
        end
        iterations = 0
        @logger.info("running first page classes and mappings of each ontology")
        @logger.flush()


        retrieve_latest_submissions.each do |acr,sub|
          @logger.info("running mapping counts #{sub.id.to_s}")
          @logger.flush()

          new_counts = LinkedData::Mappings
                    .mapping_ontologies_count(sub,nil,reload_cache=true)
          persistent_counts = {}
          LinkedData::Models::MappingCount.where(pair_count: false,
                                                 ontologies: [acr])
          .include(:all)
          .all
          .each do |m|
            other = m.ontologies.first
            if other == acr
              other = m.ontologies[1]
            end
            persistent_counts[other] = m
          end
          
          new_counts.each do |other|
            new_count = counts[other]
            if persistent_counts.include?(other)
              inst = model_count[other]
              if new_count != inst.count
                inst.count = new_count
                inst.save
              else
                m = LinkedData::Models::MappingCount.new
                m.count = new_count
                m.ontologies = [acr,other]
                m.pair_count = true
                m.save
              end
            end
          end

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

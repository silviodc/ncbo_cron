require 'logger'
require 'benchmark'

module NcboCron
  module Models
    class OntologiesReport
      class OntologiesReportError < StandardError; end

      ERROR_CODES = {
          summaryOnly:                              "Ontology is summary-only",
          flat:                                     "This ontology is designated as FLAT",
          errSummaryOnlyWithSubmissions:            "Ontology has submissions but it is set to summary-only",
          errNoSubmissions:                         "Ontology has no submissions",
          errNoReadySubmission:                     "Ontology has no submissions in a ready state",
          errNoLatestReadySubmission:               lambda { |n| "The latest submission is not ready and is ahead of the latest ready by #{n} revision#{n > 1 ? 's' : ''}" },
          errNoClassesLatestReadySubmission:        "The latest ready submission has no classes",
          errNoRootsLatestReadySubmission:          "The latest ready submission has no roots",
          errNoMetricsLatestReadySubmission:        "The latest ready submission has no metrics",
          errIncorrectMetricsLatestReadySubmission: "The latest ready submission has incorrect metrics",
          errNoAnnotator:                           lambda { |data| "Annotator - #{data[0] > 0 ? 'FEW' : 'NO'} results for: #{data[1]}" },
          errNoSearch:                              lambda { |data| "Search - #{data[0] > 0 ? 'FEW' : 'NO'} results for: #{data[1]}" },
          errRunningReport:                         lambda { |data| "Error while running report on component #{data[0]}: #{data[1]}: #{data[2]}" },
          errErrorStatus:                           [],
          errMissingStatus:                         []
      }

      def initialize(logger=nil, report_path='')
        @logger = nil
        if logger.nil?
          log_file = File.new(NcboCron.settings.log_path, "a")
          log_path = File.dirname(File.absolute_path(log_file))
          log_filename_no_ext = File.basename(log_file, ".*")
          ontologies_report_log_path = File.join(log_path, "#{log_filename_no_ext}-ontologies-report.log")
          @logger = Logger.new(ontologies_report_log_path)
        else
          @logger = logger
        end
        @report_path = report_path.empty? ? NcboCron.settings.ontology_report_path : report_path
        @stop_words = Annotator.settings.stop_words_default_list
      end

      def ontologies_to_include(acronyms)
        ont_to_include = acronyms
        if acronyms.empty?
          ont_to_include = []
          # ont_to_include = ["PHENOMEBLAST", "MYOBI", "NCBIVIRUSESTAX", "OntoOrpha", "PERTANIAN", "PHENOMEBLAST", "RTEST-LOINC", "SSACAL", "TEST", "UU", "VIRUSESTAX"]
          # ont_to_include = ["AERO", "SBO", "EHDAA", "CCO", "ONLIRA", "VT", "ZEA", "SMASH", "PLIO", "OGI", "CO", "NCIT", "GO"]
          # ont_to_include = ["AEO", "DATA-CITE", "FLOPO", "ICF-d8", "OGG-MM", "PP", "PROV", "TESTONTOO"]
        end
        ont_to_include
      end

      def run
        ont_to_include = ontologies_to_include([])
        refresh_report(ont_to_include)
      end

      def refresh_report(acronyms=[])
        ont_to_include = ontologies_to_include(acronyms)
        info_msg = 'Running ontologies report for'
        ontologies_msg = ''
        update_msg = ''
        report = empty_report
        ontologies = LinkedData::Models::Ontology.where.include(:acronym).all
        ontologies.select! { |ont| ont_to_include.include?(ont.acronym) } unless ont_to_include.empty?

        if acronyms.empty?
          ontologies_msg = 'ALL ontologies'
          update_msg = 'generating'
        else
          ontologies_msg = "ontologies #{acronyms.join(", ")}"
          update_msg = 'updating'
        end

        @logger.info("#{info_msg} #{ontologies_msg}...\n")
        count = 0

        ontologies.each do |ont|
          count += 1
          @logger.info("Processing report for #{ont.acronym} - #{count} of #{ontologies.length} ontologies."); @logger.flush
          time = Benchmark.realtime do
            report[:ontologies][ont.acronym.to_sym] = generate_single_ontology_report(ont)
          end
          @logger.info("Finished report for #{ont.acronym} in #{time} sec."); @logger.flush
        end

        lock_key = "ONTOLOGIES_REPORT_LOCK"
        lock = redis.get(lock_key)

        while lock do
          sleep(2)
          lock = redis.get(lock_key)
        end

        begin
          redis.setex lock_key, 10, true
          report_to_write = acronyms.empty? ? empty_report : ontologies_report(true)
          report_to_write[:ontologies].merge!(report[:ontologies])
          ontology_report_date(report_to_write, "report_date_generated") if acronyms.empty?
          File.open(@report_path, 'w') { |file| file.write(::JSON.pretty_generate(report_to_write)) }
        ensure
          redis.del(lock_key)
        end
        @logger.info("Finished #{update_msg} report for #{ontologies_msg}. Wrote report data to #{@report_path}.\n"); @logger.flush
      end

      def ontologies_report(suppress_error=false)
        report = empty_report
        report_file_exists = File.exist?(@report_path)

        if !suppress_error && !report_file_exists
          raise OntologiesReportError, "Ontologies report file #{@report_path} not found"
        end

        if report_file_exists
          json_string = ::IO.read(@report_path)
          report = ::JSON.parse(json_string, :symbolize_names => true)
        end
        report
      end

      def delete_ontologies_from_report(acronyms=[])
        report_file_exists = File.exist?(@report_path)

        if report_file_exists && !acronyms.empty?
          report = ontologies_report(true)

          unless report[:ontologies].empty?
            acronyms.each { |acronym| report[:ontologies].delete acronym.to_sym }
            File.open(@report_path, 'w') { |file| file.write(::JSON.pretty_generate(report)) }
          end
        end
      end

      private

      def empty_report
        {ontologies: {}, report_date_generated: nil}
      end

      def generate_single_ontology_report(ont)
        report = {problem: false, format: '', date_created: '', logFilePath: '', report_date_updated: nil}
        ont.bring_remaining()
        ont.bring(:submissions)
        submissions = ont.submissions

        # first see if is summary only and if it has submissions
        if ont.summaryOnly
          if !submissions.nil? && submissions.length > 0
            add_error_code(report, :errSummaryOnlyWithSubmissions)
          else
            add_error_code(report, :summaryOnly)
          end
          ontology_report_date(report, "report_date_updated")
          return report
        end

        # check if latest submission is the one ready
        latest_any = ont.latest_submission(status: :any)
        if latest_any.nil?
          # no submissions, cannot continue
          add_error_code(report, :errNoSubmissions)
          ontology_report_date(report, "report_date_updated")
          return report
        end

        # add creationDate of the first submission (AKA "ontology creation date")
        first_sub = submissions.sort_by{ |sub| sub.id }.first
        first_sub.bring(:creationDate)
        ontology_report_date(report, "date_created", first_sub.creationDate)

        # path to most recent log file
        log_file_path = log_file(ont.acronym, latest_any.submissionId.to_s)
        report[:logFilePath] = log_file_path unless log_file_path.empty?

        # ontology format
        latest_any.bring(:hasOntologyLanguage)
        format_obj = latest_any.hasOntologyLanguage
        report[:format] = format_obj.get_code_from_id if format_obj

        latest_ready = ont.latest_submission
        if latest_ready.nil?
          # no ready submission exists, cannot continue
          add_error_code(report, :errNoReadySubmission)
          # add error statuses from the latest non-ready submission
          latest_any.submissionStatus.each { |st| add_error_code(report, :errErrorStatus, st.get_code_from_id) if st.error? }
          ontology_report_date(report, "report_date_updated")
          return report
        end

        # submission that's ready is not the latest one
        if latest_any.id.to_s != latest_ready.id.to_s
          sub_count = 0
          latest_submission_id = latest_ready.submissionId.to_i
          ont.submissions.each { |sub| sub_count += 1 if sub.submissionId.to_i > latest_submission_id }
          add_error_code(report, :errNoLatestReadySubmission, sub_count)
        end

        # rest of the tests run for latest_ready
        sub = latest_ready
        sub.bring_remaining()
        sub.ontology.bring_remaining()
        sub.bring(:metrics)

        # add error statuses
        sub.submissionStatus.each { |st| add_error_code(report, :errErrorStatus, st.get_code_from_id) if st.error? }

        # add missing statuses
        statuses = LinkedData::Models::SubmissionStatus.where.all
        statuses.select! { |st| !st.error? }
        statuses.select! { |st| st.id.to_s["DIFF"].nil? }
        statuses.select! { |st| st.id.to_s["ARCHIVED"].nil? }
        statuses.select! { |st| st.id.to_s["RDF_LABELS"].nil? }

        statuses.each do |ok|
          found = false

          sub.submissionStatus.each do |st|
            if st == ok
              found = true
              break
            end
          end
          add_error_code(report, :errMissingStatus, ok.get_code_from_id) unless found
        end

        # check whether ontology has been designated as "flat" or root classes exist
        if sub.ontology.flat
          add_error_code(report, :flat)
        else
          begin
            add_error_code(report, :errNoRootsLatestSubmission) unless sub.roots().length > 0
          rescue Exception => e
            add_error_code(report, :errNoRootsLatestSubmission)
            add_error_code(report, :errRunningReport, ["sub.roots()", e.class, e.message])
          end
        end

        # check if metrics has been generated
        metrics = sub.metrics

        if metrics.nil?
          add_error_code(report, :errNoMetricsLatestSubmission)
        else
          metrics.bring_remaining

          if metrics.classes + metrics.properties < 10
            add_error_code(report, :errIncorrectMetricsLatestSubmission)
          end
        end

        # check if classes exist
        good_classes = good_classes(sub)

        if good_classes.empty?
          add_error_code(report, :errNoClassesLatestSubmission)
        else
          delim = " | "
          search_text = good_classes.join(delim)

          # check for Annotator calls
          ann = Annotator::Models::NcboAnnotator.new(@logger)
          ann_response = ann.annotate(search_text, { ontologies: [ont.acronym] })

          if ann_response.length < good_classes.length
            ann_search_terms = []

            good_classes.each do |cls|
              ann_response_term = ann.annotate(cls, { ontologies: [ont.acronym] })
              ann_search_terms << (ann_response_term.empty? ? "<span class='missing_term'>#{cls}</span>" : cls)
            end
            add_error_code(report, :errNoAnnotator, [ann_response.length, ann_search_terms.join(delim)])
          end

          # check for Search calls
          search_resp = LinkedData::Models::Class.search(solr_escape(search_text), search_query_params(ont.acronym))

          if search_resp["response"]["numFound"] < good_classes.length
            search_search_terms = []

            good_classes.each do |cls|
              search_response_term = LinkedData::Models::Class.search(solr_escape(cls), search_query_params(ont.acronym))
              search_search_terms << (search_response_term["response"]["numFound"] > 0 ? cls : "<span class='missing_term'>#{cls}</span>")
            end
            add_error_code(report, :errNoSearch, [search_resp["response"]["numFound"], search_search_terms.join(delim)])
          end
        end
        ontology_report_date(report, "report_date_updated")
        report
      end

      def ontology_report_date(report, date_str, tm=Time.new)
        tm_str = tm.strftime("%m/%d/%Y %I:%M%p")
        report[date_str.to_sym] = tm_str
      end

      def good_classes(submission)
        page_num = 1
        page_size = 1000
        classes_size = 10
        good_classes = Array.new
        paging = LinkedData::Models::Class.in(submission).include(:prefLabel, :synonym).page(page_num, page_size)

        begin
          page_classes = nil

          begin
            page_classes = paging.page(page_num, page_size).all
          rescue Exception =>  e
            # some obscure error that happens intermittently
            @logger.error("#{e.class}: #{e.message}")
            @logger.error("Sub: #{submission.id}")
            throw e
          end

          break if page_classes.empty?

          page_classes.each do |cls|
            prefLabel = nil

            begin
              prefLabel = cls.prefLabel
            rescue Goo::Base::AttributeNotLoaded =>  e
              next
            end

            # Skip classes with no prefLabel, short prefLabel, b-nodes, or stop-words
            next if prefLabel.nil? || prefLabel.length < 3 ||
                cls.id.to_s.include?(".well-known/genid") || @stop_words.include?(prefLabel.upcase)

            # store good prefLabel
            good_classes << prefLabel
            break if good_classes.length === classes_size
          end

          page_num = (good_classes.length === classes_size || !page_classes.next?) ? nil : page_num + 1
        end while !page_num.nil?
        good_classes
      end

      def log_file(acronym, submission_id)
        log_file_path = ''

        begin
          ont_repo_path = Dir.open("#{LinkedData.settings.repository_folder}/#{acronym}/#{submission_id}")
          log_file_path = Dir.glob(File.join(ont_repo_path, '*.log')).max_by {|f| File.mtime(f)}
          log_file_path.sub!(/^#{LinkedData.settings.repository_folder}\//, '') if log_file_path
        rescue Exception => e
          # no log file or dir exists
        end
        log_file_path ||= ''
      end

      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end

      def add_error_code(report, code, data=nil)
        report[:problem] = false unless report.has_key? :problem
        if ERROR_CODES.has_key? code
          if ERROR_CODES[code].kind_of?(Array)
            unless data.nil?
              report[code] = [] unless report.has_key? code
              report[code] << data
            end
          elsif ERROR_CODES[code].is_a? (Proc)
            unless data.nil?
              report[code] = ERROR_CODES[code].call(data)
            end
          else
            report[code] = ERROR_CODES[code]
          end
          report[:problem] = true if code.to_s.start_with? "err"
        end
      end

      def search_query_params(acronym)
        return {
          "defType" => "edismax",
          "stopwords" => "true",
          "lowercaseOperators" => "true",
          "fl" => "*,score",
          "hl" => "on",
          "hl.simple.pre" => "<em>",
          "hl.simple.post" => "</em>",
          "qf" => "resource_id^100 prefLabelExact^90 prefLabel^70 synonymExact^50 synonym^10 notation cui semanticType",
          "hl.fl" => "resource_id prefLabelExact prefLabel synonymExact synonym notation cui semanticType",
          "fq" => "submissionAcronym:\"#{acronym}\" AND obsolete:false",
          "page" => 1,
          "pagesize" => 50,
          "start" => 0,
          "rows" => 50
        }
      end

      def redis
        Redis.new(host: Annotator.settings.annotator_redis_host, port: Annotator.settings.annotator_redis_port)
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
# ontologies_report_path = File.join("logs", "ontologies-report.log")
# ontologies_report_logger = Logger.new(ontologies_report_path)
# NcboCron::Models::OntologiesReport.new(ontologies_report_logger).run
# ./bin/ncbo_cron --disable-processing true --disable-pull true --disable-flush true --disable-warmq true --disable-ontology-analytics true --ontologies-report '22 * * * *'
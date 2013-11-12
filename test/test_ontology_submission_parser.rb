require_relative 'test_case'
require 'json'
require 'multi_json'
require 'redis'

class TestOntologySubmission < TestCase

  def self.before_suite
    @@redis = Redis.new(:host => $QUEUE_REDIS_HOST, :port => $QUEUE_REDIS_PORT)
    db_size = @@redis.dbsize

    if db_size > 2000
      puts "This test cannot be run. You are probably pointing to the wrong redis backend. "
      return
    end

    #for annotator dict creation
    tmp_folder = "./test/tmp/"
    if not Dir.exist? tmp_folder
      FileUtils.mkdir_p tmp_folder
    end

    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER

    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ont_count, @@acronyms, @@ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 2, submission_count: 2, process_submission: false)
  end

  def self.after_suite
    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_queue_submission
    parser = NcboCron::Models::OntologySubmissionParser.new

    o1 = @@ontologies[0]
    o1.bring(:submissions) if o1.bring?(:submissions)
    parser.queue_submission(o1.submissions[0], {dummy_action: true})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o1.submissions[0].id.to_s))
    assert_nil val

    parser.queue_submission(o1.submissions[0], {
        dummy_action: true, index_search: false, metrics: true,
        process_annotator: true, another_dummy_action: true, all: true})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o1.submissions[0].id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal NcboCron::Models::OntologySubmissionParser::ACTIONS, options

    o2 = @@ontologies[1]
    o2.bring(:submissions) if o2.bring?(:submissions)
    parser.queue_submission(o2.submissions[0], {
        :process_rdf => false, :index_search => true, :metrics => true,
        :process_annotator => false})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o2.submissions[0].id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal({:process_rdf => false, :index_search => true, :process_annotator => false}, options)
  end

  def test_parse_submissions
    parser = NcboCron::Models::OntologySubmissionParser.new

    submission_ids = [1,2]
    archived_submissions = []
    not_archived_submissions = []
    submission_ids.each do |id|
      o1 = @@ontologies[0]
      o1.bring(:submissions) if o1.bring?(:submissions)
      sub1 = o1.submissions.select { |x| x.id.to_s["/submissions/#{id}"]}.first
      sub1.bring(:submissionStatus) if sub1.bring?(:submissionStatus)

      o2 = @@ontologies[1]
      o2.bring(:submissions) if o2.bring?(:submissions)
      sub2 = o2.submissions.select { |x| x.id.to_s["/submissions/#{id}"]}.first
      sub2.bring(:submissionStatus) if sub2.bring?(:submissionStatus)

      parser.queue_submission(sub1, {
          :dummy_action => true, :process_rdf => true, :index_search => true,
          :dummy_metrics => false, :run_metrics => false, :process_annotator => false,
          :another_dummy_action => false, :all => false})
      parser.queue_submission(sub2, {
          dummy_action: false, process_rdf: true, index_search: false,
          dummy_metrics: true, run_metrics: false, process_annotator: true,
          another_dummy_action: true, all: false})

      parser.process_queue_submissions

      sub1 = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(sub1.id)).first
      sub1.bring(:submissionStatus) if sub1.bring?(:submissionStatus)
      sub2 = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(sub2.id)).first
      sub2.bring(:submissionStatus) if sub2.bring?(:submissionStatus)
      sub1statusCodes = LinkedData::Models::SubmissionStatus.get_status_codes(sub1.submissionStatus)
      assert_equal [], ["UPLOADED", "RDF", "RDF_LABELS", "INDEXED"] - sub1statusCodes
      sub2statusCodes = LinkedData::Models::SubmissionStatus.get_status_codes(sub2.submissionStatus)
      assert_equal [], ["UPLOADED", "RDF", "RDF_LABELS", "ANNOTATOR"] - sub2statusCodes
      if id > 1
        [o1,o2].each do |os|
          os.submissions.each do |s|
            s.bring(:submissionStatus)
            s.bring(:submissionId)
            if s.submissionId == 1
              assert s.archived?
              archived_submissions << s
            else
              not_archived_submissions << s
            end
          end
        end
      end
      # Check ontology diffs
      subs4ont1 = o1.submissions
      subs4ont1.each { |o| o.bring(:submissionId, :diffFilePath) }
      recent_submissions = subs4ont1.sort { |a,b| b.submissionId <=> a.submissionId }[0..5]
      recent_submissions.each_with_index do |s|
        if s.submissionId == 1
          assert(s.diffFilePath == nil, 'Should not create submission diff for oldest submission')
        else
          assert(s.diffFilePath != nil, 'Failed to create submission diff for a recent submission')
        end
      end
    end

    logger = Logger.new(STDOUT)
    archived_submissions.each do |s|
      assert LinkedData::Models::Class.where.in(s).all.count > 0
    end
    not_archived_submissions.each do |s|
      assert LinkedData::Models::Class.where.in(s).all.count > 50
    end
    parser.process_flush_classes(logger)
    archived_submissions.each do |s|
      assert LinkedData::Models::Class.where.in(s).all.count == 0
    end
    not_archived_submissions.each do |s|
      assert LinkedData::Models::Class.where.in(s).all.count > 50
    end

    ont_submission_iter = NcboCron::Models::QueryWarmer.new(logger).run 
    assert ont_submission_iter >= 4


    o1 = @@ontologies[0]
    o1.delete
    zombies = parser.zombie_classes_graphs
    assert zombies.length ==  1
    assert zombies.first["/TEST-ONT-0/submissions/2"]
  end

end

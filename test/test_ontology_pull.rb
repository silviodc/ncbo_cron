require_relative 'test_case'
require 'rack'

class TestOntologyPull < TestCase

  def self.before_suite
    ont_path = File.expand_path("../data/ontology_files/BRO_v3.2.owl", __FILE__)
    file = File.new(ont_path)
    port = 4567
    @@url = "http://localhost:#{port}/"
    @@thread = Thread.new do
      Rack::Server.start(
          app: lambda do |e|
            contents = file.read
            file.rewind
            [200, {'Content-Type' => 'text/plain'}, [contents]]
          end,
          Port: port
      )
    end

    @@redis = Redis.new(:host => NcboCron.settings.redis_host, :port => NcboCron.settings.redis_port)
    db_size = @@redis.dbsize

    if db_size > 2000
      puts "This test cannot be run. You are probably pointing to the wrong redis backend. "
      return
    end

    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def self.after_suite
    Thread.kill(@@thread)
    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_remote_ontology_pull()
    ontologies = init_ontologies(1)
    ont = LinkedData::Models::Ontology.find(ontologies[0].id).first
    ont.bring(:submissions) if ont.bring?(:submissions)
    assert_equal 1, ont.submissions.length

    pull = NcboCron::Models::OntologyPull.new
    pull.do_remote_ontology_pull()

    # check that the pull creates a new submission when the file has changed
    ont = LinkedData::Models::Ontology.find(ontologies[0].id).first
    ont.bring(:submissions) if ont.bring?(:submissions)
    assert_equal 2, ont.submissions.length

    new_sub = ont.latest_submission(status: :uploaded)
    new_sub.bring_remaining()
    assert_equal 2, new_sub.submissionId
    assert_equal ontologies[0].submissions[0].pullLocation, new_sub.pullLocation
    assert ontologies[0].submissions[0].released < new_sub.released

    # test Redis queue
    queue = NcboCron::Models::OntologySubmissionParser.new
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, queue.get_prefixed_id(new_sub.id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal NcboCron::Models::OntologySubmissionParser::ACTIONS, options

    # check that the pull does not create a new submission when the file has not changed
    ontologies = init_ontologies(2)
    ont = LinkedData::Models::Ontology.find(ontologies[0].id).first
    ont.bring(:submissions) if ont.bring?(:submissions)
    assert_equal 2, ont.submissions.length
    pull.do_remote_ontology_pull()
    assert_equal 2, ont.submissions.length
  end

  private

  def init_ontologies(submission_count)
    ont_count, acronyms, ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1, submission_count: submission_count, process_submission: false)
    ontologies[0].bring(:submissions) if ontologies[0].bring?(:submissions)
    ontologies[0].submissions.each do |sub|
      sub.bring_remaining()
      sub.pullLocation = RDF::IRI.new(@@url)
      sub.save()
    end
    return ontologies
  end

end

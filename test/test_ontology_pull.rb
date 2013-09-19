require_relative 'test_case'
require 'rack'

class TestOntologyPull < TestCase

  def self.before_suite
    # CREATE FILE OBJECT:
    file = File.new("#{LinkedData.settings.repository_folder}/BROTEST-0/1/BRO_v3.2.owl")
    #file = File.new("#{LinkedData.settings.repository_folder}/TEST-ONT-0/1/BRO_v3.1.owl")

    @@thread = Thread.new do
      Rack::Server.start(
          app: lambda do |e|
            contents = file.read
            file.rewind
            [200, {'Content-Type' => 'text/plain'}, [contents]]
          end,
          Port: 4567
      )
    end

    @@redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
    db_size = @@redis.dbsize

    if db_size > 2000
      puts "This test cannot be run. You are probably pointing to the wrong redis backend. "
      return
    end

    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER

    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ont_count, @@acronyms, @@ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: false)
    @@ontologies[0].bring(:submissions) if @@ontologies[0].bring?(:submissions)
    @@ontologies[0].submissions[0].bring_remaining()
    @@ontologies[0].submissions[0].pullLocation = RDF::IRI.new("http://localhost:4567/")
    @@ontologies[0].submissions[0].save()
  end

  def self.after_suite
    Thread.kill(@@thread)
    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_remote_ontology_pull()
    pull = NcboCron::Models::OntologyPull.new
    pull.do_remote_ontology_pull()
    ont = LinkedData::Models::Ontology.find(@@ontologies[0].id).first
    ont.bring(:submissions) if ont.bring?(:submissions)
    assert_equal 2, ont.submissions.length

    new_sub = ont.latest_submission(status: :uploaded)
    new_sub.bring_remaining()
    assert_equal 2, new_sub.submissionId
    assert_equal @@ontologies[0].submissions[0].pullLocation, new_sub.pullLocation
    assert @@ontologies[0].submissions[0].released < new_sub.released

    # test Redis queue
    queue = NcboCron::Models::OntologySubmissionParser.new
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, queue.get_prefixed_id(new_sub.id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal NcboCron::Models::OntologySubmissionParser::ACTIONS, options
  end
end

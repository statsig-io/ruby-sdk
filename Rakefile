require 'rake/testtask'
require 'parallel_tests/tasks'

desc 'Run unit tests'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.test_files = FileList['test/**/*.rb'].exclude('test/mock_server.rb', 'test/dummy_data_adapter.rb')
  t.verbose = true
  t.warning = false
end

task default: :test

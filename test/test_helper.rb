require 'simplecov'
require 'simplecov-lcov'
SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov.formatter = ENV['LCOV'] ? SimpleCov::Formatter::LcovFormatter : SimpleCov::Formatter::HTMLFormatter
SimpleCov.start { add_filter '/test/' } if ENV['COVERAGE']

require 'minitest/autorun'

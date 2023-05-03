# typed: ignore

require 'simplecov'
require 'simplecov-lcov'
require 'simplecov-cobertura'
SimpleCov.formatter = if ENV['COVERAGE_FORMAT'] == 'cobertura'
                        SimpleCov::Formatter::CoberturaFormatter
                      elsif ENV['COVERAGE_FORMAT'] == 'lcov'
                        SimpleCov::Formatter::LcovFormatter
                      else
                        SimpleCov::Formatter::HTMLFormatter
                      end
SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov.start { add_filter '/test/' } if ENV['COVERAGE']

require 'minitest/autorun'

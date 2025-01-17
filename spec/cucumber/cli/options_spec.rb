# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'cucumber/cli/options'

module Cucumber
  module Cli
    describe Options do
      def given_cucumber_yml_defined_as(hash_or_string)
        allow(File).to receive(:exist?) { true }

        cucumber_yml = hash_or_string.is_a?(Hash) ? hash_or_string.to_yaml : hash_or_string

        allow(IO).to receive(:read).with('cucumber.yml') { cucumber_yml }
      end

      before(:each) do
        allow(File).to receive(:exist?) { false } # Meaning, no cucumber.yml exists
        allow(Kernel).to receive(:exit)
      end

      def output_stream
        @output_stream ||= StringIO.new
      end

      def error_stream
        @error_stream ||= StringIO.new
      end

      def options
        @options ||= Options.new(output_stream, error_stream)
      end

      def prepare_args(args)
        args.is_a?(Array) ? args : args.split(' ')
      end

      describe 'parsing' do
        def when_parsing(args)
          yield
          options.parse!(prepare_args(args))
        end

        def after_parsing(args)
          options.parse!(prepare_args(args))
          yield
        end

        def with_env(name, value)
          previous_value = ENV[name]
          ENV[name] = value.to_s
          yield
          if previous_value.nil?
            ENV.delete(name)
          else
            ENV[name] = previous_value
          end
        end

        context '-r or --require' do
          it 'collects all specified files into an array' do
            after_parsing('--require some_file.rb -r another_file.rb') do
              expect(options[:require]).to eq ['some_file.rb', 'another_file.rb']
            end
          end
        end

        context '--i18n-languages' do
          include RSpec::WorkInProgress

          it 'lists all known languages' do
            after_parsing '--i18n-languages' do
              ::Gherkin::DIALECTS.keys.map do |key|
                expect(@output_stream.string).to include(key.to_s)
              end
            end
          end

          it 'exits the program' do
            when_parsing('--i18n-languages') { expect(Kernel).to receive(:exit) }
          end
        end

        context '--i18n-keywords' do
          context 'with invalid LANG' do
            include RSpec::WorkInProgress

            it 'exits' do
              when_parsing '--i18n-keywords foo' do
                expect(Kernel).to receive(:exit)
              end
            end

            it 'says the language was invalid' do
              after_parsing '--i18n-keywords foo' do
                expect(@output_stream.string).to include("Invalid language 'foo'. Available languages are:")
              end
            end

            it 'displays the language table' do
              after_parsing '--i18n-keywords foo' do
                ::Gherkin::DIALECTS.keys.map do |key|
                  expect(@output_stream.string).to include(key.to_s)
                end
              end
            end
          end
        end

        context '-f FORMAT or --format FORMAT' do
          it 'defaults the output for the formatter to the output stream (STDOUT)' do
            after_parsing('-f pretty') { expect(options[:formats]).to eq [['pretty', {}, output_stream]] }
          end

          it 'extracts per-formatter options' do
            after_parsing('-f pretty,foo=bar,foo2=bar2') do
              expect(options[:formats]).to eq [['pretty', { 'foo' => 'bar', 'foo2' => 'bar2' }, output_stream]]
            end
          end

          it 'extracts junit formatter file attribute option' do
            after_parsing('-f junit,file-attribute=true') do
              expect(options[:formats]).to eq [['junit', { 'file-attribute' => 'true' }, output_stream]]
            end
          end

          it 'extracts junit formatter file attribute option with pretty' do
            after_parsing('-f pretty -f junit,file-attribute=true -o file.txt') do
              expect(options[:formats]).to eq [['pretty', {}, output_stream], ['junit', { 'file-attribute' => 'true' }, 'file.txt']]
            end
          end
        end

        context '-o [FILE|DIR] or --out [FILE|DIR]' do
          it "defaults the formatter to 'pretty' when not specified earlier" do
            after_parsing('-o file.txt') { expect(options[:formats]).to eq [['pretty', {}, 'file.txt']] }
          end
          it 'sets the output for the formatter defined immediately before it' do
            after_parsing('-f profile --out file.txt -f pretty -o file2.txt') do
              expect(options[:formats]).to eq [['profile', {}, 'file.txt'], ['pretty', {}, 'file2.txt']]
            end
          end
        end

        context 'handling multiple formatters' do
          it 'catches multiple command line formatters using the same stream' do
            expect { options.parse!(prepare_args('-f pretty -f progress')) }.to raise_error('All but one formatter must use --out, only one can print to each stream (or STDOUT)')
          end

          it 'catches multiple profile formatters using the same stream' do
            given_cucumber_yml_defined_as('default' => '-f progress -f pretty')
            options = Options.new(output_stream, error_stream, default_profile: 'default')

            expect { options.parse!(%w[]) }.to raise_error('All but one formatter must use --out, only one can print to each stream (or STDOUT)')
          end

          it 'profiles does not affect the catching of multiple command line formatters using the same stream' do
            given_cucumber_yml_defined_as('default' => '-q')
            options = Options.new(output_stream, error_stream, default_profile: 'default')

            expect { options.parse!(%w[-f progress -f pretty]) }.to raise_error('All but one formatter must use --out, only one can print to each stream (or STDOUT)')
          end

          it 'merges profile formatters and command line formatters' do
            given_cucumber_yml_defined_as('default' => '-f junit -o result.xml')
            options = Options.new(output_stream, error_stream, default_profile: 'default')

            options.parse!(%w[-f pretty])

            expect(options[:formats]).to eq [['pretty', {}, output_stream], ['junit', {}, 'result.xml']]
          end
        end

        context '-t TAGS --tags TAGS' do
          it 'handles tag expressions as argument' do
            after_parsing(['--tags', 'not @foo or @bar']) { expect(options[:tag_expressions]).to eq ['not @foo or @bar'] }
          end

          it 'stores tags passed with different --tags separately' do
            after_parsing('--tags @foo --tags @bar') { expect(options[:tag_expressions]).to eq ['@foo', '@bar'] }
          end

          it 'strips tag limits from the tag expressions stored' do
            after_parsing(['--tags', 'not @foo:2 or @bar:3']) { expect(options[:tag_expressions]).to eq ['not @foo or @bar'] }
          end

          it 'stores tag limits separately' do
            after_parsing(['--tags', 'not @foo:2 or @bar:3']) { expect(options[:tag_limits]).to eq Hash('@foo' => 2, '@bar' => 3) }
          end

          it 'raise exception for inconsistent tag limits' do
            expect { after_parsing('--tags @foo:2 --tags @foo:3') }.to raise_error(RuntimeError, 'Inconsistent tag limits for @foo: 2 and 3')
          end
        end

        context '-n NAME or --name NAME' do
          it 'stores the provided names as regular expressions' do
            after_parsing('-n foo --name bar') { expect(options[:name_regexps]).to eq [/foo/, /bar/] }
          end
        end

        context '-e PATTERN or --exclude PATTERN' do
          it 'stores the provided exclusions as regular expressions' do
            after_parsing('-e foo --exclude bar') { expect(options[:excludes]).to eq [/foo/, /bar/] }
          end
        end

        context '-l LINES or --lines LINES' do
          it 'adds line numbers to args' do
            options.parse!(%w[-l24 FILE])

            expect(options.instance_variable_get(:@args)).to eq ['FILE:24']
          end
        end

        context '-p PROFILE or --profile PROFILE' do
          it 'uses the default profile passed in during initialization if none are specified by the user' do
            given_cucumber_yml_defined_as('default' => '--require some_file')

            options = Options.new(output_stream, error_stream, default_profile: 'default')
            options.parse!(%w[--format progress])

            expect(options[:require]).to include('some_file')
          end

          it 'merges all uniq values from both cmd line and the profile' do
            given_cucumber_yml_defined_as('foo' => %w[--verbose])
            options.parse!(%w[--wip --profile foo])

            expect(options[:wip]).to be true
            expect(options[:verbose]).to be true
          end

          it "gives precendene to the origianl options' paths" do
            given_cucumber_yml_defined_as('foo' => %w[features])
            options.parse!(%w[my.feature -p foo])

            expect(options[:paths]).to eq %w[my.feature]
          end

          it 'combines the require files of both' do
            given_cucumber_yml_defined_as('bar' => %w[--require features -r dog.rb])
            options.parse!(%w[--require foo.rb -p bar])

            expect(options[:require]).to eq %w[foo.rb features dog.rb]
          end

          it 'combines the tag names of both' do
            given_cucumber_yml_defined_as('baz' => %w[-t @bar])
            options.parse!(%w[--tags @foo -p baz])

            expect(options[:tag_expressions]).to eq ['@foo', '@bar']
          end

          it 'combines the tag limits of both' do
            given_cucumber_yml_defined_as('baz' => %w[-t @bar:2])
            options.parse!(%w[--tags @foo:3 -p baz])

            expect(options[:tag_limits]).to eq Hash('@foo' => 3, '@bar' => 2)
          end

          it 'raise exceptions for inconsistent tag limits' do
            given_cucumber_yml_defined_as('baz' => %w[-t @bar:2])

            expect { options.parse!(%w[--tags @bar:3 -p baz]) }.to raise_error(RuntimeError, 'Inconsistent tag limits for @bar: 3 and 2')
          end

          it 'only takes the paths from the original options, and disgregards the profiles' do
            given_cucumber_yml_defined_as('baz' => %w[features])
            options.parse!(%w[my.feature -p baz])

            expect(options[:paths]).to eq ['my.feature']
          end

          it 'uses the paths from the profile when none are specified originally' do
            given_cucumber_yml_defined_as('baz' => %w[some.feature])
            options.parse!(%w[-p baz])

            expect(options[:paths]).to eq ['some.feature']
          end

          it 'combines environment variables from the profile but gives precendene to cmd line args' do
            given_cucumber_yml_defined_as('baz' => %w[FOO=bar CHEESE=swiss])
            options.parse!(%w[-p baz CHEESE=cheddar BAR=foo])

            expect(options[:env_vars]).to eq('BAR' => 'foo', 'FOO' => 'bar', 'CHEESE' => 'cheddar')
          end

          it 'disregards STDOUT formatter defined in profile when another is passed in (via cmd line)' do
            given_cucumber_yml_defined_as('foo' => %w[--format pretty])
            options.parse!(%w[--format progress --profile foo])

            expect(options[:formats]).to eq [['progress', {}, output_stream]]
          end

          it 'includes any non-STDOUT formatters from the profile' do
            given_cucumber_yml_defined_as('json' => %w[--format json -o features.json])
            options.parse!(%w[--format progress --profile json])

            expect(options[:formats]).to eq [['progress', {}, output_stream], ['json', {}, 'features.json']]
          end

          it 'does not include STDOUT formatters from the profile if there is a STDOUT formatter in command line' do
            given_cucumber_yml_defined_as('json' => %w[--format json -o features.json --format pretty])
            options.parse!(%w[--format progress --profile json])

            expect(options[:formats]).to eq [['progress', {}, output_stream], ['json', {}, 'features.json']]
          end

          it 'includes any STDOUT formatters from the profile if no STDOUT formatter was specified in command line' do
            given_cucumber_yml_defined_as('json' => %w[--format json])
            options.parse!(%w[--format rerun -o rerun.txt --profile json])

            expect(options[:formats]).to eq [['json', {}, output_stream], ['rerun', {}, 'rerun.txt']]
          end

          it 'assumes all of the formatters defined in the profile when none are specified on cmd line' do
            given_cucumber_yml_defined_as('json' => %w[--format progress --format json -o features.json])
            options.parse!(%w[--profile json])

            expect(options[:formats]).to eq [['progress', {}, output_stream], ['json', {}, 'features.json']]
          end

          # rubocop:disable Style/GlobalVars
          it 'only reads cucumber.yml once' do
            original_parse_count = $cucumber_yml_read_count
            $cucumber_yml_read_count = 0

            begin
              given_cucumber_yml_defined_as(<<-YML
              <% $cucumber_yml_read_count += 1 %>
              default: --format pretty
              YML
                                           )
              options = Options.new(output_stream, error_stream, default_profile: 'default')
              options.parse!(%w[-f progress])

              expect($cucumber_yml_read_count).to eq 1
            ensure
              $cucumber_yml_read_count = original_parse_count
            end
          end
          # rubocop:enable Style/GlobalVars

          it 'respects --quiet when defined in the profile' do
            given_cucumber_yml_defined_as('foo' => '-q')
            options.parse!(%w[-p foo])

            expect(options[:publish_quiet]).to be true
            expect(options[:snippets]).to be false
            expect(options[:source]).to be false
            expect(options[:duration]).to be false
          end

          it 'uses --no-duration when defined in the profile' do
            given_cucumber_yml_defined_as('foo' => '--no-duration')
            options.parse!(%w[-p foo])

            expect(options[:duration]).to be false
          end

          context '--retry ATTEMPTS' do
            context '--retry option not defined on the command line' do
              it 'uses the --retry option from the profile' do
                given_cucumber_yml_defined_as('foo' => '--retry 2')
                options.parse!(%w[-p foo])

                expect(options[:retry]).to be 2
              end
            end

            context '--retry option defined on the command line' do
              it 'ignores the --retry option from the profile' do
                given_cucumber_yml_defined_as('foo' => '--retry 2')
                options.parse!(%w[--retry 1 -p foo])

                expect(options[:retry]).to be 1
              end
            end
          end

          context '--retry-total TESTS' do
            context '--retry-total option not defined on the command line' do
              it 'uses the --retry-total option from the profile' do
                given_cucumber_yml_defined_as('foo' => '--retry-total 2')
                options.parse!(%w[-p foo])

                expect(options[:retry_total]).to be 2
              end
            end

            context '--retry-total option defined on the command line' do
              it 'ignores the --retry-total option from the profile' do
                given_cucumber_yml_defined_as('foo' => '--retry-total 2')
                options.parse!(%w[--retry-total 1 -p foo])

                expect(options[:retry_total]).to be 1
              end
            end
          end
        end

        context '-P or --no-profile' do
          it 'disables profiles' do
            given_cucumber_yml_defined_as('default' => '-v --require file_specified_in_default_profile.rb')

            after_parsing('-P --require some_file.rb') do
              expect(options[:require]).to eq ['some_file.rb']
            end
          end

          it 'notifies the user that the profiles are being disabled' do
            given_cucumber_yml_defined_as('default' => '-v')

            after_parsing('--no-profile --require some_file.rb') do
              expect(output_stream.string).to match(/Disabling profiles.../)
            end
          end
        end

        context '-b or --backtrace' do
          it "turns on cucumber's full backtrace" do
            when_parsing('-b') do
              expect(Cucumber).to receive(:use_full_backtrace=).with(true)
            end
          end
        end

        context '--version' do
          it "displays Cucumber's version" do
            after_parsing('--version') do
              expect(output_stream.string).to match(/#{Cucumber::VERSION}/)
            end
          end

          it 'exits the program' do
            when_parsing('--version') { expect(Kernel).to receive(:exit) }
          end
        end

        context 'environment variables (i.e. MODE=webrat)' do
          it 'places all of the environment variables into a hash' do
            after_parsing('MODE=webrat FOO=bar') do
              expect(options[:env_vars]).to eq('MODE' => 'webrat', 'FOO' => 'bar')
            end
          end
        end

        context '--retry ATTEMPTS' do
          it 'is 0 by default' do
            after_parsing('') do
              expect(options[:retry]).to eql 0
            end
          end

          it 'sets the options[:retry] value' do
            after_parsing('--retry 4') do
              expect(options[:retry]).to eql 4
            end
          end
        end

        context '--retry-total TESTS' do
          it 'is INFINITY by default' do
            after_parsing('') do
              expect(options[:retry_total]).to eql Float::INFINITY
            end
          end

          it 'sets the options[:retry_total] value' do
            after_parsing('--retry 3 --retry-total 10') do
              expect(options[:retry_total]).to eql 10
            end
          end
        end

        it 'assigns any extra arguments as paths to features' do
          after_parsing('-f pretty my_feature.feature my_other_features') do
            expect(options[:paths]).to eq ['my_feature.feature', 'my_other_features']
          end
        end

        it 'does not mistake environment variables as feature paths' do
          after_parsing('my_feature.feature FOO=bar') do
            expect(options[:paths]).to eq ['my_feature.feature']
          end
        end

        context '--snippet-type' do
          it 'parses the snippet type argument' do
            after_parsing('--snippet-type classic') do
              expect(options[:snippet_type]).to eq :classic
            end
          end
        end

        context '--publish' do
          it 'adds message formatter with output to default reports publishing url' do
            after_parsing('--publish') do
              expect(@options[:formats]).to include(['message', {}, Cucumber::Cli::Options::CUCUMBER_PUBLISH_URL])
            end
          end

          it 'enables publishing when CUCUMBER_PUBLISH_ENABLED=true' do
            with_env('CUCUMBER_PUBLISH_ENABLED', 'true') do
              after_parsing('') do
                expect(@options[:formats]).to include(['message', {}, Cucumber::Cli::Options::CUCUMBER_PUBLISH_URL])
                expect(@options[:publish_enabled]).to be true
              end
            end
          end

          it 'does not enable publishing when CUCUMBER_PUBLISH_ENABLED=false' do
            with_env('CUCUMBER_PUBLISH_ENABLED', 'false') do
              after_parsing('') do
                expect(@options[:publish_enabled]).to be_falsy
              end
            end
          end

          it 'adds authentication header with CUCUMBER_PUBLISH_TOKEN environment variable value if set' do
            with_env('CUCUMBER_PUBLISH_TOKEN', 'abcd1234') do
              after_parsing('--publish') do
                expect(@options[:formats]).to include(['message', {}, %(#{Cucumber::Cli::Options::CUCUMBER_PUBLISH_URL} -H "Authorization: Bearer abcd1234")])
                expect(@options[:publish_enabled]).to be true
              end
            end
          end

          it 'adds authentication header with CUCUMBER_PUBLISH_TOKEN environment variable value if set and no --publish' do
            with_env('CUCUMBER_PUBLISH_TOKEN', 'abcd1234') do
              after_parsing('') do
                expect(@options[:formats]).to include(['message', {}, %(#{Cucumber::Cli::Options::CUCUMBER_PUBLISH_URL} -H "Authorization: Bearer abcd1234")])
                expect(@options[:publish_enabled]).to be true
              end
            end
          end
        end

        context '--publish-quiet' do
          it 'silences publish banner' do
            after_parsing('--publish-quiet') do
              expect(@options[:publish_quiet]).to eq true
            end
          end

          it 'enables publishing when CUCUMBER_PUBLISH_QUIET=true' do
            with_env('CUCUMBER_PUBLISH_QUIET', 'true') do
              after_parsing('') do
                expect(@options[:publish_quiet]).to be true
              end
            end
          end
        end
      end

      describe 'dry-run' do
        it 'has the default value for snippets' do
          given_cucumber_yml_defined_as('foo' => %w[--dry-run])
          options.parse!(%w[--dry-run])

          expect(options[:snippets]).to be true
        end

        it 'sets snippets to false when no-snippets provided after dry-run' do
          given_cucumber_yml_defined_as('foo' => %w[--dry-run --no-snippets])
          options.parse!(%w[--dry-run --no-snippets])

          expect(options[:snippets]).to be false
        end

        it 'sets snippets to false when no-snippets provided before dry-run' do
          given_cucumber_yml_defined_as('foo' => %w[--no-snippet --dry-run])
          options.parse!(%w[--no-snippets --dry-run])

          expect(options[:snippets]).to be false
        end
      end
    end
  end
end

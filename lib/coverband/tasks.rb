# frozen_string_literal: true

namespace :coverband do
  def safely_import_files(files_to_cover)
    if files_to_cover.any?
      files = Coverband::Baseline.exclude_files(files_to_cover)

      files.each do |file|
        begin
          require_dependency file
        rescue Exception => err
          if Coverband.configuration.verbose
            Coverband.configuration.logger.error "error adding file to baseline: #{file}"
            Coverband.configuration.logger.error "error: #{err}"
            Coverband.configuration.logger.error "#{err.backtrace.join("\n")}"
          end
        end
      end
    end
  end

  desc 'record coverband coverage baseline'
  task :baseline do
    Coverband::Baseline.record do
      safely_import_files(Coverband.configuration.additional_files.flatten)
      if Rake::Task.tasks.any? { |key| key.to_s.match(/environment$/) }
        Coverband.configuration.logger.info 'invoking rake environment'
        Rake::Task['environment'].invoke
      elsif Rake::Task.tasks.any? { |key| key.to_s.match(/env$/) }
        Coverband.configuration.logger.info 'invoking rake env'
        Rake::Task['env'].invoke
      end

      baseline_files = [File.expand_path('./config/boot.rb', Dir.pwd),
                        File.expand_path('./config/application.rb', Dir.pwd),
                        File.expand_path('./config/environment.rb', Dir.pwd)]

      baseline_files.each do |baseline_file|
        require baseline_file if File.exist?(baseline_file)
      end

      if defined? Rails
        Rails.application.eager_load!
        safely_import_files(Dir.glob("#{Rails.root}/app/**/*.rb"))
        if File.exist?("#{Rails.root}/lib")
          safely_import_files(Dir.glob("#{Rails.root}/lib/**/*.rb"))
        end
      end
    end

    def self.convert_coverage_format(results)
      file_map = {}
      results.each_pair do |file, data|
        lines_map = {}
        data.each_with_index do |hits, index|
          lines_map[(index + 1)] = hits unless hits.nil?
        end
        file_map[file] = lines_map
      end
      file_map
    end

    project_directory = File.expand_path(Coverband.configuration.root)
    results = convert_coverage_format(Coverband::Baseline.results.reject { |key, _val| !key.match(project_directory) || Coverband.configuration.ignore.any? { |pattern| key.match(/#{pattern}/) } })
    results_check = results.reject { |_key, val| val.empty? }

    rds = Coverband.configuration.redis
    cnt = 0
    i = 0
    until cnt >= results_check.count
      cnt = rds.keys.select { |x| x.include?("coverband2") }.count
      puts "i: #{i} cnt: #{cnt}"
      if i > 120
        puts "Error: Redis timeout after '#{i}' attempts count '#{cnt}'"
        break
      end
      i+=1
      sleep 1
    end


    redis_keys = rds.keys.select { |x| x.include?("coverband2") }
    app = redis_keys.select { |x| x.include?("coverband2") }.select { |x| x.include?("#{pwd}/app/") }
    lib = redis_keys.select { |x| x.include?("coverband2") }.select { |x| x.include?("#{pwd}/lib/") }
    engines = redis_keys.select { |x| x.include?("coverband2") }.select { |x| x.include?("#{pwd}/vendor/engines/") }
    common_coverband_lines = redis_keys.reject {|x| x == "coverband2"}.inject(0){|sum, x| sum + (rds.hgetall(x).count) }

    # common_lines = 0
    # code_lines = 0
    # covered = 0
    # redis_keys.each { |item|
    #   common_lines += item.count
    #   code_lines += item.select { |i| !i.nil? }.count
    #   covered += item.select { |i| !i.nil? }.select { |i| i > 0 }.count
    # }
    #
    # puts "Total lines: #{common_lines}"
    # puts "Code lines: #{code_lines}"
    # puts "Covered lines: #{covered}"
    require 'socket'
    puts "Redis stats on '#{Socket.gethostname}':"
    puts "----------------"
    puts "total                #{redis_keys.count}"
    puts "total without empty  #{results_check.count}"
    puts "app                  #{app.count}"
    puts "lib                  #{lib.count}"
    puts "vendor/engines       #{engines.count}"
    puts "common lines collect #{common_coverband_lines}"
  end

  ###
  # note: If your project has set many simplecov filters.
  # You might want to override them and clear the filters.
  # Or run the task `coverage_no_filters` below.
  ###
  desc 'report runtime coverband code coverage'
  task coverage: :environment do
    if Coverband.configuration.reporter == 'scov'
      Coverband::Reporters::SimpleCovReport.report(Coverband.configuration.store)
    else
      Coverband::Reporters::ConsoleReport.report(Coverband.configuration.store)
    end
  end

  def clear_simplecov_filters
    SimpleCov.filters.clear if defined? SimpleCov
  end

  desc 'report runtime coverband code coverage after disabling simplecov filters'
  task coverage_no_filters: :environment do
    if Coverband.configuration.reporter == 'scov'
      clear_simplecov_filters
      Coverband::Reporters::SimpleCovReport.report(Coverband.configuration.store)
    else
      puts 'coverage without filters only makes sense for SimpleCov reports'
    end
  end

  ###
  # You likely want to clear coverage after significant code changes.
  # You may want to have a hook that saves current coverband data on deploy
  # and then resets the coverband store data.
  ###
  desc 'reset coverband coverage data'
  task clear: :environment do
    Coverband.configuration.store.clear!
  end
end

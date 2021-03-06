require 'digest'
require 'tmpdir'
require 'pathname'
require 'rufus-lru'
require 'set'
require 'delegate'

module RSpecBackgroundProcess
	class ProcessPool
		class ProcessDefinition
			def initialize(pool, group, path, type, options)
				@pool = pool
				@group = group
				@path = path
				@type = type

				@extensions = Set.new
				@options = {
					ready_timeout: 10,
					term_timeout: 10,
					kill_timeout: 10,
					ready_test: ->(p){fail 'no readiness check defined'},
					refresh_action: ->(p){p.restart},
					logging: false
				}.merge(options)
				@working_directory = nil
				@arguments = []
			end

			attr_accessor :group
			attr_reader :path

			def initialize_copy(old)
				# need own copy
				@extensions = @extensions.dup
				@options = @options.dup
				@arguments = @arguments.dup
			end

			def with
				process = dup
				yield process
				process
			end

			def extend(mod, options = {})
				@extensions << mod
				@options.merge! options
			end

			def logging_enabled
				@options[:logging] = true
			end

			def logging_enabled?
				@options[:logging]
			end

			def ready_test(&block)
				@options[:ready_test] = block
			end

			def refresh_action(&block)
				@options[:refresh_action] = block
			end

			def ready_timeout(seconds)
				@options[:ready_timeout] = seconds
			end

			def term_timeout(seconds)
				@options[:term_timeout] = seconds
			end

			def kill_timeout(seconds)
				@options[:kill_timeout] = seconds
			end

			def working_directory(dir)
				@working_directory = dir
			end

			def arguments
				@arguments
			end

			def argument(*value)
				@arguments += value
			end

			def instance
				# disallow changes to the definition once we have instantiated
				@options.freeze
				@arguments.freeze
				@working_directory.freeze
				@extensions.freeze

				# instance is requested
				# we calculate key based on current definition
				_key = key

				# already crated
				if instance = @pool[_key]
					# always make sure options are up to date with definition
					instance.reset_options(@options)
					return instance
				end

				# can only use parts of the key for instance name
				name = Pathname.new(@path).basename

				# need to crate new one
				instance = @type.new(
					"#{@group}-#{name}-#{_key}",
					@path,
					@arguments,
					@working_directory || [name, _key],
					@options
				)

				# ports get allocated here...
				@extensions.each do |mod|
					instance.extend(mod)
				end

				@pool[_key] = instance
			end

			# shortcut
			def start
				instance.start
			end

			def key
				hash = Digest::SHA256.new
				hash.update @group.to_s
				hash.update @path.to_s
				hash.update @type.name
				@extensions.each do |mod|
					hash.update mod.name
				end
				hash.update @working_directory.to_s
				@arguments.each do |argument|
					case argument
					when Pathname
						begin
							# use file content as part of the hash
							hash.update argument.read
						rescue Errno::ENOENT
							# use file name if it does not exist
							hash.update argument.to_s
						end
					else
						hash.update argument.to_s
					end
				end
				Digest.hexencode(hash.digest)[0..16]
			end
		end

		class LRUPool
			class VoidHash < Hash
				def []=(key, value)
					value
				end
			end

			def initialize(max_running, &lru_stop)
				@all = {}
				@max_running = max_running
				@running_keep = max_running > 0 ? LruHash.new(max_running) : VoidHash.new
				@running_all = Set[]
				@active = Set[]

				@after_store = []
				@lru_stop = lru_stop
			end

			def to_s
				"LRUPool[all: #{@all.length}, running: #{@running_all.length}, active: #{@active.map(&:to_s).join(',')}, keep: #{@running_keep.length}]"
			end

			def []=(key, value)
				@active << key
				@all[key] = value
				@after_store.each{|callback| callback.call(key, value)}
			end

			def [](key)
				if @all.member? key
					@active << key
					@running_keep[key] # bump on use if on running LRU list
				end
				@all[key]
			end

			def delete(key)
				@running_keep.delete(key)
				@running_all.delete(key)
				@active.delete(key)
				@all.delete(key)
			end

			def instances
				@all.values
			end

			def reset_active
				puts "WARNING: There are more active processes than max running allowed! Consider increasing max running from #{@max_running} to #{@active.length} or more." if @max_running < @active.length
				@active = Set.new
				trim!
			end

			def running(key)
				return unless @all.member? key
				@running_keep[key] = key
				@running_all << key
				trim!
			end

			def not_running(key)
				@running_keep.delete(key)
				@running_all.delete(key)
			end

			def after_store(&callback)
				@after_store << callback
			end

			private

			def trim!
				to_stop.each do |key|
					@lru_stop.call(key, @all[key])
				end
			end

			def to_stop
				@running_all - @active - @running_keep.values
			end
		end

		def initialize(options)
			@stats = {}

			@max_running = options.delete(:max_running) || 4

			@pool = LRUPool.new(@max_running) do |key, instance|
				#puts "too many instances running, stopping: #{instance.name}[#{key}]; #{@pool}"
				stats(instance.name)[:lru_stopped] += 1
				instance.stop
			end

			# keep track of running instances
			@pool.after_store do |key, instance|
				instance.after_state_change do |new_state|
					# we mark running before it is actually started to have a chance to stop over-limit instance first
					if new_state == :starting
						#puts "new instance running: #{instance.name}[#{key}]"
						@pool.running(key)
						stats(instance.name)[:started] += 1
					end
					@pool.not_running(key) if [:not_running, :dead, :jammed].include? new_state
				end

				# mark running if added while already running
				@pool.running(key) if instance.running?

				# init stats
				stats(instance.name)[:started] ||= 0
				stats(instance.name)[:lru_stopped] ||= 0
			end

			# for storing shared data
			@global_context = {}

			# for filling template strings with actual instance data
			@template_renderer = ->(variables, string) {
				out = string.dup
				variables.merge(
					/project directory/ => -> { Dir.pwd.to_s }
				).each do |regexp, source|
					out.gsub!(/<#{regexp}>/) do
						source.call(*$~.captures)
					end
				end
				out
			}

			# this are passed down to instance
			@options = options.merge(
				global_context:  @global_context,
				template_renderer: @template_renderer
			)
		end

		attr_reader :pool
		attr_reader :options

		def logging_enabled?
			@options[:logging]
		end

		def cleanup
			@pool.reset_active
		end

		def stats(name)
			@stats[name] ||= {}
		end

		def report_stats
			puts
			puts "Process pool stats (max running: #{@max_running}):"
			@stats.each do |key, stats|
				puts "  #{key}: #{stats.map{|k, v| "#{k}: #{v}"}.join(' ')}"
			end
			puts "Total instances: #{@stats.length}"
			puts "Total starts: #{@stats.reduce(0){|total, stat| total += stat.last[:started]}}"
			puts "Total LRU stops: #{@stats.reduce(0){|total, stat| total += stat.last[:lru_stopped]}}"
			puts "Total extra LRU stops: #{@stats.reduce(0){|total, stat| extra = (stat.last[:lru_stopped] - 1); total += extra if extra > 0; total}}"
		end

		def failed_instance
			@pool.instances.select do |instance|
				instance.dead? or
				instance.failed? or
				instance.jammed?
			end.sort_by do |instance|
				instance.state_change_time
			end.last
		end

		def report_failed_instance
			if failed_instance
				puts "Last failed process instance state log: "
				failed_instance.state_log.each do |log_line|
					puts "\t#{log_line}"
				end
				puts "Working directory: #{failed_instance.working_directory}"
				puts "Log file: #{failed_instance.log_file}"
				puts "State: #{failed_instance.state}"
				puts "Exit code: #{failed_instance.exit_code}"
			else
				puts "No process instance in failed state"
			end
		end

		def report_logs
			puts "Process instance logs:"
			@pool.instances.each do |instance|
				puts "#{instance.name}: #{instance.log_file}"
			end
		end
	end
end

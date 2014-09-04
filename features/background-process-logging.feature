Feature: Handling of output and logging
	All process output is written to a log file.

	Background:
		Given test background process executable is features/support/test_process
		And test process is ready when log file contains hello world
		Given test2 background process executable is features/support/test_process
		And test2 process is ready when log file contains hello world
		Given bogus background process executable is features/support/bogus
		Given unkillable background process executable is features/support/test_process
		And unkillable process termination timeout is 0.0 second
		And unkillable process kill timeout is 0.0 second

	@logging @output
	Scenario: Output from background process is logged to a log file
		Given test process argument foo bar
		And fresh test process is running and ready
		Then test process log should contain foo bar

	@logging @output
	Scenario: By default process state changes are not logged
		And fresh test process is running and ready
		Then stopping test process will not print anything

	@logging @output
	Scenario: When logging is enabled process state changes are logged to STDOUT
		Given test process logging is enabled
		And fresh test process is running and ready
		Then stopping test process will print process is now not_running

	#@logging @output
	#Scenario: Process will output history of state changes when something goes wrong
	#	Given bogus process is running
	#	And I wait 1 seconds for process to settle
	#	Then bogus process should be dead
	#	Given unkillable process is running
	#	Then unkillable process should fail to stop
	#	Then unkillable process should be jammed
	#	Given this scenario fail
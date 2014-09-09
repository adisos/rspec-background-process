Feature: Managing current working directory
	Current working directory for the process by default is autogenerated temporary directory that is unique for process definition life time.

	Background:
		Given ruby background process ruby script is features/support/test_process
		And ruby process is ready when log file contains hello world
		Given ruby2 background process ruby script is features/support/test_process
		And ruby2 process is ready when log file contains hello world
		Given exec background process ruby script is features/support/test_process
		And exec process is ready when log file contains hello world
		Given exec2 background process ruby script is features/support/test_process
		And exec2 process is ready when log file contains hello world

	@cwd @ruby
	Scenario: By default process is started in unique temporary directory
		Given fresh ruby process instance is running and ready
		When we remember ruby process instance reported current directory
		Given fresh ruby2 process instance is running and ready
		Then remembered process current directory is different from ruby2 process instance reported one

	@cwd @exec
	Scenario: By default process is started in unique temporary directory
		Given fresh exec process instance is running and ready
		When we remember exec process instance reported current directory
		Given fresh exec2 process instance is running and ready
		Then remembered process current directory is different from exec2 process instance reported one

	@cwd @ruby
	Scenario: Process current directory changes does not affect our test current directory
		Given we remember current working directory
		And fresh ruby process instance is running and ready
		Then current working directory is unchanged

	@cwd @exec
	Scenario: Process current directory changes does not affect our test current directory
		Given we remember current working directory
		And fresh exec process instance is running and ready
		Then current working directory is unchanged

	@cwd
	Scenario: Process current working directory configurable to current working directory
		Given we remember current working directory
		Given ruby process working directory is the same as current working directory
		Given fresh ruby process instance is running and ready
		Then current working directory is unchanged
		Then ruby process instance reports it's current working directory to be the same as current directory

	@cwd
	Scenario: The current working directory should be configurable to provided directory
		Given ruby process working directory is changed to tmp/test
		Given fresh ruby process instance is running and ready
		Then ruby process instance reports it's current working directory to be relative to current working directory by tmp/test


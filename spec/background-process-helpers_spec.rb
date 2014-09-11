require_relative 'spec_helper'

describe SpawnProcessHelpers do
	describe '#process_pool' do
		it 'should provide singleton pool object ' do
			p1 = process_pool
			p2 = process_pool

			expect(p1).to eq(p2)
		end
	end

	describe '#background_process' do
		it 'should allow specifying executable to run' do
			process = background_process('features/support/test_process')
			expect(process.instance.command).to include 'features/support/test_process'
		end

		describe 'load option' do
			it 'when set to true will change instance type to LoadedBackgroundProcess' do
				process = background_process('features/support/test_process', load: true)
				expect(process.instance).to be_a CucumberSpawnProcess::LoadedBackgroundProcess
			end
		end

		it 'should return process definition' do
			process = background_process('features/support/test_process')
			expect(process).to be_a CucumberSpawnProcess::ProcessPool::ProcessDefinition
		end
	end
end
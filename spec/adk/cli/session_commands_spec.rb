# # frozen_string_literal: true

# require 'spec_helper'
# require 'adk/cli/session_commands'
# require 'adk/session_service/redis'
# require 'adk/session'
# require 'timecop'
# require 'thor'

# RSpec.describe ADK::CLI::SessionCommands do
#   let(:session_service_double) { instance_double(ADK::SessionService::Redis) }
#   let(:output) { StringIO.new }
#   # Initialize Basic shell without arguments
#   let(:shell) { Thor::Shell::Basic.new }
#   subject(:cli) { described_class.new }

#   before do
#     # Stub the initializer for the Redis session service
#     allow(ADK::SessionService::Redis).to receive(:new).and_return(session_service_double)

#     # Configure the shell instance to use our StringIO for output capture
#     # Thor commands use `@shell` internally. We need to make sure the instance
#     # the command uses has its output configured.
#     allow(shell).to receive(:stdout).and_return(output)
#     allow(shell).to receive(:stderr).and_return(output) # Capture stderr too if needed

#     # Stub the `shell` method on the CLI instance to return our configured shell
#     allow(cli).to receive(:shell).and_return(shell)

#     # Freeze time for consistent created_at formatting
#     Timecop.freeze(Time.parse('2024-01-01 10:00:00 UTC'))
#   end

#   after do
#     Timecop.return
#   end

#   describe '#list' do
#     context 'when no sessions are found' do
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: nil, user_id: nil).and_return([])
#       end

#       it 'prints a message indicating no sessions were found' do
#         cli.list
#         expect(output.string).to include("No sessions found.")
#       end
#     end

#     context 'when sessions exist' do
#       let(:session1) do
#         ADK::Session.new(id: 'sess_1', app_name: 'app1', user_id: 'user1', events: [])
#       end
#       let(:session2) do
#         Timecop.freeze(Time.now - 3600) do
#           ADK::Session.new(id: 'sess_2', app_name: 'app2', user_id: 'user2', events: [])
#         end
#       end
#       let(:sessions) { [session1, session2] }

#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: nil, user_id: nil).and_return(sessions)
#         allow(session1).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#         allow(session2).to receive(:created_at).and_return(Time.parse('2024-01-01 09:00:00 UTC').iso8601)
#       end

#       it 'prints the list of sessions' do
#         cli.list
#         expect(output.string).to include("Found 2 session(s):")
#         expect(output.string).to include("ID: sess_1")
#         expect(output.string).to include("App: app1")
#         expect(output.string).to include("User: user1")
#         expect(output.string).to include("Created: 2024-01-01 10:00:00")
#         expect(output.string).to include("Events: 0")
#         expect(output.string).to include("ID: sess_2")
#         expect(output.string).to include("App: app2")
#         expect(output.string).to include("User: user2")
#         expect(output.string).to include("Created: 2024-01-01 09:00:00")
#         expect(output.string).to include("Events: 0")
#       end
#     end

#     context 'when filtering by app_name using option' do
#       let(:session1) do
#         ADK::Session.new(id: 'sess_1', app_name: 'app1', user_id: 'user1', events: [])
#       end
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'app1',
#                                                                       user_id: nil).and_return([session1])
#         allow(session1).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'prints only sessions matching the app_name' do
#         cli.invoke(:list, [], { app_name: 'app1' })
#         expect(output.string).to include("Found 1 session(s):")
#         expect(output.string).to include("ID: sess_1")
#         expect(output.string).to include("App: app1")
#         expect(output.string).not_to include("ID: sess_2")
#       end

#       it 'prints a message indicating filter criteria when no sessions found' do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'nonexistent',
#                                                                       user_id: nil).and_return([])
#         cli.invoke(:list, [], { app_name: 'nonexistent' })
#         expect(output.string).to include("No sessions found for app 'nonexistent'")
#       end
#     end

#     context 'when filtering by user_id using option' do
#       let(:session1) do
#         ADK::Session.new(id: 'sess_1', app_name: 'app1', user_id: 'user1', events: [])
#       end
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: nil,
#                                                                       user_id: 'user1').and_return([session1])
#         allow(session1).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'prints only sessions matching the user_id' do
#         cli.invoke(:list, [], { user_id: 'user1' })
#         expect(output.string).to include("Found 1 session(s):")
#         expect(output.string).to include("ID: sess_1")
#         expect(output.string).to include("User: user1")
#         expect(output.string).not_to include("ID: sess_2")
#       end

#       it 'prints a message indicating filter criteria when no sessions found' do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: nil,
#                                                                       user_id: 'nonexistent').and_return([])
#         cli.invoke(:list, [], { user_id: 'nonexistent' })
#         expect(output.string).to include("No sessions found and user 'nonexistent'") # Wording from the command
#       end
#     end

#     context 'when filtering by app_name and user_id using options' do
#       let(:session1) do
#         ADK::Session.new(id: 'sess_1', app_name: 'app1', user_id: 'user1', events: [])
#       end
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'app1',
#                                                                       user_id: 'user1').and_return([session1])
#         allow(session1).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'prints only sessions matching both app_name and user_id' do
#         cli.invoke(:list, [], { app_name: 'app1', user_id: 'user1' })
#         expect(output.string).to include("Found 1 session(s):")
#         expect(output.string).to include("ID: sess_1")
#         expect(output.string).to include("App: app1")
#         expect(output.string).to include("User: user1")
#       end

#       it 'prints a message indicating filter criteria when no sessions found' do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'app1',
#                                                                       user_id: 'nonexistent').and_return([])
#         cli.invoke(:list, [], { app_name: 'app1', user_id: 'nonexistent' })
#         expect(output.string).to include("No sessions found for app 'app1' and user 'nonexistent'")
#       end
#     end

#     context 'when filtering using positional arguments' do
#       let(:session1) do
#         ADK::Session.new(id: 'sess_1', app_name: 'app1', user_id: 'user1', events: [])
#       end
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'app1',
#                                                                       user_id: 'user1').and_return([session1])
#         allow(session1).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'uses positional arguments for app_name and user_id' do
#         cli.invoke(:list, ['app1', 'user1'])
#         expect(session_service_double).to have_received(:list_sessions).with(app_name: 'app1', user_id: 'user1')
#         expect(output.string).to include("Found 1 session(s):")
#         expect(output.string).to include("ID: sess_1")
#       end
#     end

#     context 'when mixing options and positional arguments' do
#       before do
#         allow(session_service_double).to receive(:list_sessions).with(app_name: 'option_app',
#                                                                       user_id: 'option_user').and_return([])
#       end

#       it 'prioritizes options over positional arguments' do
#         # invoke takes positional args first, then options hash
#         cli.invoke(:list, ['positional_app', 'positional_user'], { app_name: 'option_app', user_id: 'option_user' })
#         # Verify the service was called with option values
#         expect(session_service_double).to have_received(:list_sessions).with(app_name: 'option_app',
#                                                                              user_id: 'option_user')
#         expect(output.string).to include("No sessions found for app 'option_app' and user 'option_user'")
#       end
#     end
#   end

#   describe '#show' do
#     let(:session_id) { 'sess_show_1' }

#     context 'when the session is not found' do
#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(nil)
#       end

#       it 'prints a not found message' do
#         cli.show(session_id)
#         expect(output.string).to include("Session '#{session_id}' not found.")
#       end
#     end

#     context 'when the session is found with no events' do
#       let(:session) do
#         ADK::Session.new(id: session_id, app_name: 'show_app', user_id: 'show_user', events: [])
#       end

#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(session)
#         allow(session).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'prints session details and a no events message' do
#         cli.show(session_id)
#         expect(output.string).to include("Session Details:")
#         expect(output.string).to include("ID: #{session_id}")
#         expect(output.string).to include("App: show_app")
#         expect(output.string).to include("User: show_user")
#         expect(output.string).to include("Created: 2024-01-01 10:00:00")
#         expect(output.string).to include("Events: 0")
#         expect(output.string).to include("No events in this session.")
#       end
#     end

#     context 'when the session is found with events' do
#       let(:events) do
#         [
#           ADK::Event.new(role: :user, content: 'Hello'),
#           ADK::Event.new(role: :agent, content: 'Hi there!')
#         ]
#       end
#       let(:session) do
#         ADK::Session.new(id: session_id, app_name: 'show_app', user_id: 'show_user', events: events)
#       end

#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(session)
#         allow(session).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       end

#       it 'prints session details and formatted events' do
#         cli.show(session_id)
#         expect(output.string).to include("Session Details:")
#         expect(output.string).to include("ID: #{session_id}")
#         expect(output.string).to include("Events: 2")
#         expect(output.string).to include("\nEvents:")
#         expect(output.string).to include("  1. [user] \"Hello\"")
#         expect(output.string).to include("  2. [agent] \"Hi there!\"")
#         expect(output.string).not_to include("No events in this session.")
#       end
#     end
#   end

#   describe '#delete' do
#     let(:session_id) { 'sess_delete_1' }
#     let(:existing_session) do
#       ADK::Session.new(id: session_id, app_name: 'delete_app', user_id: 'delete_user', events: [])
#     end

#     context 'when the session is not found' do
#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(nil)
#         allow(cli).to receive(:yes?).and_return(false)
#       end

#       it 'prints a not found message and does not attempt deletion' do
#         expect(session_service_double).not_to receive(:delete_session)
#         cli.delete(session_id)
#         expect(output.string).to include("Session '#{session_id}' not found.")
#       end
#     end

#     context 'when the session exists but user cancels deletion' do
#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(existing_session)
#         allow(cli).to receive(:yes?).with("Are you sure you want to delete session '#{session_id}'? (y/n)").and_return(false)
#       end

#       it 'prints a cancellation message and does not delete' do
#         expect(session_service_double).not_to receive(:delete_session)
#         cli.delete(session_id)
#         expect(output.string).to include("Deletion cancelled.")
#       end
#     end

#     context 'when the session exists and user confirms deletion' do
#       before do
#         allow(session_service_double).to receive(:get_session).with(session_id: session_id).and_return(existing_session)
#         allow(cli).to receive(:yes?).with("Are you sure you want to delete session '#{session_id}'? (y/n)").and_return(true)
#       end

#       context 'and deletion is successful' do
#         before do
#           allow(session_service_double).to receive(:delete_session).with(session_id: session_id).and_return(true)
#         end

#         it 'prints a success message' do
#           cli.delete(session_id)
#           expect(output.string).to include("Session '#{session_id}' deleted successfully.")
#         end
#       end

#       context 'and deletion fails' do
#         before do
#           allow(session_service_double).to receive(:delete_session).with(session_id: session_id).and_return(false)
#         end

#         it 'prints a failure message' do
#           cli.delete(session_id)
#           expect(output.string).to include("Failed to delete session '#{session_id}'.")
#         end
#       end
#     end
#   end

#   describe '#execute' do
#     let(:agent_name) { 'test_agent' }
#     let(:task) { 'perform the test task' }
#     let(:redis_double) { instance_double(Redis) }
#     let(:agent_commands_double) { instance_double(ADK::CLI::AgentCommands) }
#     let(:existing_session_id) { 'sess_existing_123' }
#     let(:new_session_id) { 'sess_new_456' }
#     let(:existing_session) do
#       ADK::Session.new(id: existing_session_id, app_name: agent_name, user_id: 'cli_user', events: [])
#     end
#     let(:new_session) do
#       ADK::Session.new(id: new_session_id, app_name: agent_name, user_id: 'cli_user', events: [])
#     end

#     before do
#       allow(Redis).to receive(:new).and_return(redis_double)
#       allow(ADK::CLI::AgentCommands).to receive(:new).and_return(agent_commands_double)
#       allow(agent_commands_double).to receive(:invoke)
#       allow(existing_session).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#       allow(new_session).to receive(:created_at).and_return(Time.parse('2024-01-01 10:00:00 UTC').iso8601)
#     end

#     context 'when agent definition is not found in Redis' do
#       before do
#         allow(redis_double).to receive(:hmget)
#           .with("adk:agent:#{agent_name}", 'description', 'tools', 'model')
#           .and_return([nil, nil, nil]) # No description means agent not found
#       end

#       it 'prints an error message and exits' do
#         expect(Kernel).to receive(:exit).with(1)
#         cli.execute(agent_name, task)
#         expect(output.string).to include("Error: Agent definition '#{agent_name}' not found.")
#         expect(agent_commands_double).not_to have_received(:invoke)
#       end
#     end

#     context 'when agent definition is found' do
#       before do
#         allow(redis_double).to receive(:hmget)
#           .with("adk:agent:#{agent_name}", 'description', 'tools', 'model')
#           .and_return(['Agent Description', '[]', 'gpt-4'])
#         allow(session_service_double).to receive(:get_session)
#         allow(session_service_double).to receive(:create_session)
#       end

#       context 'and an existing session_id is provided and found' do
#         before do
#           allow(session_service_double).to receive(:get_session).with(session_id: existing_session_id).and_return(existing_session)
#         end

#         it 'uses the existing session and invokes agent execute' do
#           cli.invoke(:execute, [agent_name, task], { session_id: existing_session_id })
#           expect(output.string).to include("Using existing Redis session: #{existing_session_id}")
#           expect(session_service_double).not_to have_received(:create_session)
#           expect(agent_commands_double).to have_received(:invoke)
#             .with(:execute, [agent_name, task], { session_id: existing_session_id, session_service: session_service_double })
#         end
#       end

#       context 'and a session_id is provided but not found' do
#         before do
#           allow(session_service_double).to receive(:get_session).with(session_id: 'not_found_id').and_return(nil)
#           allow(session_service_double).to receive(:create_session).with(app_name: agent_name, user_id: 'cli_user').and_return(new_session)
#         end

#         it 'prints a warning, creates a new session, and invokes agent execute' do
#           cli.invoke(:execute, [agent_name, task], { session_id: 'not_found_id' })
#           expect(output.string).to include("Warning: Session ID 'not_found_id' provided but not found. Starting a new session.")
#           expect(output.string).to include("Started new Redis session: #{new_session_id}")
#           expect(agent_commands_double).to have_received(:invoke)
#             .with(:execute, [agent_name, task], { session_id: new_session_id, session_service: session_service_double })
#         end
#       end

#       context 'and no session_id is provided' do
#         before do
#           allow(session_service_double).to receive(:create_session).with(app_name: agent_name, user_id: 'cli_user').and_return(new_session)
#         end

#         it 'creates a new session and invokes agent execute' do
#           cli.invoke(:execute, [agent_name, task])
#           expect(session_service_double).not_to have_received(:get_session)
#           expect(output.string).to include("Started new Redis session: #{new_session_id}")
#           expect(agent_commands_double).to have_received(:invoke)
#             .with(:execute, [agent_name, task], { session_id: new_session_id, session_service: session_service_double })
#         end
#       end
#     end
#   end
# end

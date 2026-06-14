# frozen_string_literal: true

require 'spec_helper'
require 'legate/generators/code_validator'

RSpec.describe Legate::Generators::CodeValidator do
  describe '.validate_syntax!' do
    it 'accepts valid Ruby code' do
      code = <<~RUBY
        class Foo < Legate::Tool
          def perform_execution(params, context)
            { status: :success }
          end
        end
      RUBY
      expect { described_class.validate_syntax!(code) }.not_to raise_error
    end

    it 'rejects code with syntax errors' do
      code = 'def foo(; end end'
      expect { described_class.validate_syntax!(code) }
        .to raise_error(described_class::UnsafeCodeError, /syntax errors/)
    end

    it 'rejects non-Ruby text' do
      code = '<html><body>Not Ruby</body></html>'
      expect { described_class.validate_syntax!(code) }
        .to raise_error(described_class::UnsafeCodeError, /syntax errors/)
    end
  end

  describe '.validate_no_dangerous_calls!' do
    it 'accepts safe code' do
      code = <<~RUBY
        require 'legate/tool'
        class MyTool < Legate::Tool
          tool_description 'Safe tool'
          parameter :input, type: :string, required: true
          private
          def perform_execution(params, context)
            { status: :success, result: params[:input].upcase }
          end
        end
      RUBY
      expect { described_class.validate_no_dangerous_calls!(code) }.not_to raise_error
    end

    it 'rejects code with system calls' do
      code = 'system("rm -rf /")'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /system/)
    end

    it 'rejects code with exec calls' do
      code = 'exec("/bin/sh")'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /exec/)
    end

    it 'rejects code with eval' do
      code = 'eval("puts 1")'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /eval/)
    end

    it 'rejects code with instance_eval' do
      code = 'obj.instance_eval { @secret }'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /instance_eval/)
    end

    it 'rejects code with backtick execution' do
      code = '`whoami`'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /backtick/)
    end

    it 'rejects code with IO.popen' do
      code = 'IO.popen("cmd") { |io| io.read }'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /popen/)
    end

    it 'rejects code with Open3' do
      code = 'Open3.capture3("ls")'
      expect { described_class.validate_no_dangerous_calls!(code) }
        .to raise_error(described_class::UnsafeCodeError, /Open3/)
    end

    it 'does not flag dangerous words in comments' do
      code = <<~RUBY
        # This does not call system or exec
        class SafeTool
          def run
            "safe"
          end
        end
      RUBY
      expect { described_class.validate_no_dangerous_calls!(code) }.not_to raise_error
    end

    it 'does not flag dangerous words in strings' do
      code = <<~RUBY
        class SafeTool
          def run
            "system exec eval are just strings"
          end
        end
      RUBY
      expect { described_class.validate_no_dangerous_calls!(code) }.not_to raise_error
    end
  end

  describe '.validate!' do
    it 'runs both syntax and safety checks' do
      safe_code = <<~RUBY
        class Foo
          def bar
            42
          end
        end
      RUBY
      expect { described_class.validate!(safe_code) }.not_to raise_error
    end

    it 'catches syntax errors before safety checks' do
      expect { described_class.validate!('def foo(; end end') }
        .to raise_error(described_class::UnsafeCodeError, /syntax errors/)
    end

    it 'catches dangerous calls in valid Ruby' do
      expect { described_class.validate!('system("pwned")') }
        .to raise_error(described_class::UnsafeCodeError, /system/)
    end
  end
end

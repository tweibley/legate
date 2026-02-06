# frozen_string_literal: true

require 'spec_helper'
require 'adk/tool/type_coercer'

RSpec.describe ADK::Tool::TypeCoercer do
  describe '.coerce' do
    subject { described_class.coerce(value, type) }

    context 'when value is nil' do
      let(:value) { nil }
      let(:type) { :string }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with :string type' do
      let(:type) { :string }

      context 'when value is a string' do
        let(:value) { 'test' }
        it 'returns the string' do
          expect(subject).to eq('test')
        end
      end

      context 'when value is an integer' do
        let(:value) { 123 }
        it 'converts to string' do
          expect(subject).to eq('123')
        end
      end
    end

    context 'with :integer type' do
      let(:type) { :integer }

      context 'when value is an integer' do
        let(:value) { 123 }
        it 'returns the integer' do
          expect(subject).to eq(123)
        end
      end

      context 'when value is a string integer' do
        let(:value) { '123' }
        it 'converts to integer' do
          expect(subject).to eq(123)
        end
      end

      context 'when value is invalid' do
        let(:value) { 'abc' }
        it 'raises CoercionError' do
          expect { subject }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Integer/)
        end
      end
    end

    context 'with :float type' do
      let(:type) { :float }

      context 'when value is a float' do
        let(:value) { 12.34 }
        it 'returns the float' do
          expect(subject).to eq(12.34)
        end
      end

      context 'when value is a string float' do
        let(:value) { '12.34' }
        it 'converts to float' do
          expect(subject).to eq(12.34)
        end
      end

      context 'when value is invalid' do
        let(:value) { 'abc' }
        it 'raises CoercionError' do
          expect { subject }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, %r{expected Numeric/Float})
        end
      end
    end

    context 'with :boolean type' do
      let(:type) { :boolean }

      it 'returns true for true' do
        expect(described_class.coerce(true, :boolean)).to be true
      end

      it 'returns false for false' do
        expect(described_class.coerce(false, :boolean)).to be false
      end

      it 'converts "true" string to true' do
        expect(described_class.coerce('true', :boolean)).to be true
      end

      it 'converts "false" string to false' do
        expect(described_class.coerce('false', :boolean)).to be false
      end

      it 'raises error for invalid string' do
        expect { described_class.coerce('invalid', :boolean) }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Boolean/)
      end
    end

    context 'with :array type' do
      let(:type) { :array }

      it 'returns array as is' do
        expect(described_class.coerce([1, 2], :array)).to eq([1, 2])
      end

      it 'parses valid JSON array string' do
        expect(described_class.coerce('[1, 2]', :array)).to eq([1, 2])
      end

      it 'raises error for invalid JSON' do
        expect { described_class.coerce('invalid', :array) }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Array/)
      end

      it 'raises error for JSON that is not an array' do
        expect { described_class.coerce('{}', :array) }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Array/)
      end
    end

    context 'with :hash type' do
      let(:type) { :hash }

      it 'returns hash as is' do
        expect(described_class.coerce({ a: 1 }, :hash)).to eq({ a: 1 })
      end

      it 'parses valid JSON hash string' do
        expect(described_class.coerce('{"a": 1}', :hash)).to eq({ 'a' => 1 })
      end

      it 'raises error for invalid JSON' do
        expect { described_class.coerce('invalid', :hash) }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Hash/)
      end

      it 'raises error for JSON that is not a hash' do
        expect { described_class.coerce('[]', :hash) }.to raise_error(ADK::Tool::TypeCoercer::CoercionError, /expected Hash/)
      end
    end

    context 'with unknown type' do
      let(:type) { :unknown }
      let(:value) { 'test' }

      it 'returns value as is' do
        expect(subject).to eq('test')
      end
    end
  end
end

# frozen_string_literal: true

require 'schemagraphy/safe_expression'

RSpec.describe SchemaGraphy::AstGate do
  it 'allows safe code' do
    code = "'hello'.upcase"
    expect { described_class.validate!(code, context_keys: []) }.not_to raise_error
  end

  it 'blocks unsafe code' do
    code = 'system("ls")'
    expect do
      described_class.validate!(code, context_keys: [])
    end.to raise_error(SecurityError, /method not allowed: system/)
  end
end

RSpec.describe SchemaGraphy::SafeTransform do
  let(:transformer) { described_class.new({ 'name' => 'world' }) }

  it 'safely executes a simple expression' do
    result = transformer.transform("'hello '.capitalize + name")
    expect(result).to eq('Hello world')
  end

  describe 'hash operations' do
    before do
      transformer.add_context(
        'hash', {
          'user' => {
            'profile' => {
              'name' => 'Test User'
            }
          }
        })
    end

    it 'allows hash traversal with dig_path' do
      expect(transformer.transform('dig_path(hash, "user.profile.name")')).to eq('Test User')
      expect(transformer.transform('dig_path(hash, "user.missing.field")')).to be_nil
    end
  end
end

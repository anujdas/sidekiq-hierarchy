require 'spec_helper'

describe Sidekiq::Hierarchy::CallbackRegistry do
  subject(:callback_registry) { described_class.new }

  describe '#subscribe' do
    let(:callback) { ->(){} }
    it 'adds subscribers to an internal list' do
      expect(callback_registry.instance_variable_get(:@callbacks)[:event]).to be_nil

      callback_registry.subscribe(:event, callback)
      expect(callback_registry.instance_variable_get(:@callbacks)[:event]).to match [callback]

      callback_registry.subscribe(:event, callback)
      expect(callback_registry.instance_variable_get(:@callbacks)[:event]).to match [callback, callback]
    end
  end

  describe '#publish' do
    let(:action) { double(act: nil) }
    let(:callback) { ->(*args) { action.act(*args) } }
    let(:bad_callback) { ->(*args) { raise } }

    let(:event) { :event }
    let(:args) { [1, 2] }

    before do
      callback_registry.subscribe(event, bad_callback)
      callback_registry.subscribe(event, callback)
    end

    it 'calls subscribers for the given event' do
      allow(bad_callback).to receive(:call)

      callback_registry.publish(event, *args)

      expect(action).to have_received(:act).with(*args)
      expect(bad_callback).to have_received(:call).with(*args)
    end

    it 'calls all callbacks regardess of exceptions' do
      expect { callback_registry.publish(event, nil) }.to_not raise_error
      expect(action).to have_received(:act)
    end

    it 'does not call subscribers for other events' do
      callback_registry.publish(:other_event, nil)
      expect(action).to_not have_received(:act)
    end
  end
end

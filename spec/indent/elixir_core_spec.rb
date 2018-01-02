# frozen_string_literal: true

require 'spec_helper'

describe 'Indenting elixir core' do
  Dir.glob('elixir/**/*.{ex,exs}').each do |f|
    it "#{f}: retains the indentation" do
      f = File.expand_path("../../../#{f}", __FILE__)
      expect(File.read(f)).to be_elixir_indentation
    end
  end
end

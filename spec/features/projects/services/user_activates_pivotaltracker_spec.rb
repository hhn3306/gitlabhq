# frozen_string_literal: true

require 'spec_helper'

describe 'User activates PivotalTracker' do
  include_context 'project service activation'

  before do
    stub_request(:post, /.*www.pivotaltracker.com.*/)
  end

  it 'activates service', :js do
    visit_project_integration('PivotalTracker')
    fill_in('Token', with: 'verySecret')

    click_test_integration

    expect(page).to have_content('PivotalTracker activated.')
  end
end

# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_change"
require "dependabot/job"

RSpec.describe Dependabot::DependencyChange do
  subject(:dependency_change) do
    described_class.new(
      job: job,
      updated_dependencies: updated_dependencies,
      updated_dependency_files: updated_dependency_files
    )
  end

  let(:job) do
    instance_double(Dependabot::Job, ignore_conditions: [])
  end

  let(:updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        previous_version: "1.7.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
        ]
      )
    ]
  end

  let(:updated_dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  describe "#pr_message" do
    let(:github_source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "dependabot-fixtures/dependabot-test-ruby-package",
        directory: "/",
        branch: nil,
        api_endpoint: "https://api.github.com/",
        hostname: "github.com"
      )
    end

    let(:job_credentials) do
      [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        },
        { "type" => "random", "secret" => "codes" }
      ]
    end

    let(:commit_message_options) do
      {
        include_scope: true,
        prefix: "[bump]",
        prefix_development: "[bump-dev]"
      }
    end

    let(:message_builder_mock) do
      instance_double(Dependabot::PullRequestCreator::MessageBuilder, message: "Hello World!")
    end

    before do
      allow(job).to receive(:source).and_return(github_source)
      allow(job).to receive(:credentials).and_return(job_credentials)
      allow(job).to receive(:commit_message_options).and_return(commit_message_options)
      allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder_mock)
    end

    it "delegates to the Dependabot::PullRequestCreator::MessageBuilder with the correct configuration" do
      expect(Dependabot::PullRequestCreator::MessageBuilder)
        .to receive(:new).with(
          source: github_source,
          files: updated_dependency_files,
          dependencies: updated_dependencies,
          credentials: job_credentials,
          commit_message_options: commit_message_options,
          dependency_group: nil,
          pr_message_encoding: nil,
          pr_message_max_length: 65_535,
          ignore_conditions: []
        )

      expect(dependency_change.pr_message).to eql("Hello World!")
    end

    context "when a dependency group is assigned" do
      it "delegates to the Dependabot::PullRequestCreator::MessageBuilder with the group included" do
        group = Dependabot::DependencyGroup.new(name: "foo", rules: { patterns: ["*"] })

        dependency_change = described_class.new(
          job: job,
          updated_dependencies: updated_dependencies,
          updated_dependency_files: updated_dependency_files,
          dependency_group: group
        )

        expect(Dependabot::PullRequestCreator::MessageBuilder)
          .to receive(:new).with(
            source: github_source,
            files: updated_dependency_files,
            dependencies: updated_dependencies,
            credentials: job_credentials,
            commit_message_options: commit_message_options,
            dependency_group: group,
            pr_message_encoding: nil,
            pr_message_max_length: 65_535,
            ignore_conditions: []
          )

        expect(dependency_change.pr_message).to eql("Hello World!")
      end
    end
  end

  describe "#should_replace_existing_pr" do
    context "when not updating a pull request" do
      let(:job) do
        instance_double(Dependabot::Job, updating_a_pull_request?: false)
      end

      it "is false" do
        expect(dependency_change.should_replace_existing_pr?).to be false
      end
    end

    context "when updating a pull request with all dependencies matching" do
      let(:job) do
        instance_double(Dependabot::Job,
                        dependencies: ["business"],
                        updating_a_pull_request?: true)
      end

      it "returns false" do
        expect(dependency_change.should_replace_existing_pr?).to be false
      end
    end

    context "when updating a pull request with duplicate dependencies" do
      let(:job) do
        instance_double(Dependabot::Job,
                        dependencies: %w(business business),
                        updating_a_pull_request?: true)
      end

      it "returns false" do
        expect(dependency_change.should_replace_existing_pr?).to be false
      end
    end

    context "when updating a pull request with non-matching casing" do
      let(:job) do
        instance_double(Dependabot::Job,
                        dependencies: ["BuSiNeSS"],
                        updating_a_pull_request?: true)
      end

      it "returns false" do
        expect(dependency_change.should_replace_existing_pr?).to be false
      end
    end

    context "when updating a pull request with out of order dependencies" do
      let(:job) do
        instance_double(Dependabot::Job,
                        dependencies: %w(PkgB PkgA),
                        updating_a_pull_request?: true)
      end

      let(:updated_dependencies) do
        [
          Dependabot::Dependency.new(
            name: "PkgA",
            package_manager: "bundler",
            version: "1.8.0",
            previous_version: "1.7.0",
            requirements: [
              { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
            ],
            previous_requirements: [
              { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
            ]
          ),
          Dependabot::Dependency.new(
            name: "PkgB",
            package_manager: "bundler",
            version: "1.8.0",
            previous_version: "1.7.0",
            requirements: [
              { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
            ],
            previous_requirements: [
              { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
            ]
          )
        ]
      end

      it "returns false" do
        expect(dependency_change.should_replace_existing_pr?).to be false
      end
    end

    context "when updating a pull request with different dependencies" do
      let(:job) do
        instance_double(Dependabot::Job,
                        dependencies: ["contoso"],
                        updating_a_pull_request?: true)
      end

      it "returns true" do
        expect(dependency_change.should_replace_existing_pr?).to be true
      end
    end
  end

  describe "#grouped_update?" do
    it "is false by default" do
      expect(dependency_change.grouped_update?).to be false
    end

    context "when a dependency group is assigned" do
      it "is true" do
        dependency_change = described_class.new(
          job: job,
          updated_dependencies: updated_dependencies,
          updated_dependency_files: updated_dependency_files,
          dependency_group: Dependabot::DependencyGroup.new(name: "foo", rules: { patterns: ["*"] })
        )

        expect(dependency_change.grouped_update?).to be true
      end
    end
  end
end

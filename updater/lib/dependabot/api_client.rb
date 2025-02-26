# typed: strict
# frozen_string_literal: true

require "http"
require "dependabot/job"
require "dependabot/opentelemetry"
require "sorbet-runtime"

# Provides a client to access the internal Dependabot Service's API
#
# The Service acts as a relay to Core's GitHub API adapters while providing
# some co-ordination and enrichment functionality that is only relevant to
# the integrated service.
#
# This API is only available to Dependabot jobs being executed within our
# hosted infrastructure and is not open to integrators at this time.
#
module Dependabot
  class ApiError < StandardError; end

  class ApiClient
    extend T::Sig

    sig { params(base_url: String, job_id: T.any(String, Integer), job_token: String).void }
    def initialize(base_url, job_id, job_token)
      @base_url = base_url
      @job_id = job_id
      @job_token = job_token
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def create_pull_request(dependency_change, base_commit_sha)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("create_pull_request", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::DEPENDENCY_NAMES, dependency_change.humanized)

      api_url = "#{base_url}/update_jobs/#{job_id}/create_pull_request"
      data = create_pull_request_data(dependency_change, base_commit_sha)
      response = http_client.post(api_url, json: { data: data })
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    ensure
      span&.finish
    end

    # TODO: Make `base_commit_sha` part of Dependabot::DependencyChange
    # TODO: Determine if we should regenerate the PR message within core for updates
    sig { params(dependency_change: Dependabot::DependencyChange, base_commit_sha: String).void }
    def update_pull_request(dependency_change, base_commit_sha)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("update_pull_request", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::DEPENDENCY_NAMES, dependency_change.humanized)

      api_url = "#{base_url}/update_jobs/#{job_id}/update_pull_request"
      body = {
        data: {
          "dependency-names": dependency_change.updated_dependencies.map(&:name),
          "updated-dependency-files": dependency_change.updated_dependency_files_hash,
          "base-commit-sha": base_commit_sha
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    ensure
      span&.finish
    end

    sig { params(dependency_names: T.any(String, T::Array[String]), reason: T.any(String, Symbol)).void }
    def close_pull_request(dependency_names, reason)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("close_pull_request", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::PR_CLOSE_REASON, reason)

      api_url = "#{base_url}/update_jobs/#{job_id}/close_pull_request"
      body = { data: { "dependency-names": dependency_names, reason: reason } }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    ensure
      span&.finish
    end

    sig { params(error_type: T.any(String, Symbol), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_error(error_type:, error_details:)
      ::Dependabot::OpenTelemetry.record_update_job_error(job_id: job_id, error_type: error_type,
                                                          error_details: error_details)

      api_url = "#{base_url}/update_jobs/#{job_id}/record_update_job_error"
      body = {
        data: {
          "error-type": error_type,
          "error-details": error_details
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    end

    sig { params(error_type: T.any(Symbol, String), error_details: T.nilable(T::Hash[T.untyped, T.untyped])).void }
    def record_update_job_unknown_error(error_type:, error_details:)
      error_type = "unknown_error" if error_type.nil?
      ::Dependabot::OpenTelemetry.record_update_job_error(job_id: job_id, error_type: error_type,
                                                          error_details: error_details)

      api_url = "#{base_url}/update_jobs/#{job_id}/record_update_job_unknown_error"
      body = {
        data: {
          "error-type": error_type,
          "error-details": error_details
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    end

    sig { params(base_commit_sha: String).void }
    def mark_job_as_processed(base_commit_sha)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("mark_job_as_processed", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::BASE_COMMIT_SHA, base_commit_sha)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)

      api_url = "#{base_url}/update_jobs/#{job_id}/mark_as_processed"
      body = { data: { "base-commit-sha": base_commit_sha } }
      response = http_client.patch(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    ensure
      span&.finish
    end

    sig { params(dependencies: T::Array[T::Hash[Symbol, T.untyped]], dependency_files: T::Array[DependencyFile]).void }
    def update_dependency_list(dependencies, dependency_files)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("update_dependency_list", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)

      api_url = "#{base_url}/update_jobs/#{job_id}/update_dependency_list"
      body = {
        data: {
          dependencies: dependencies,
          dependency_files: dependency_files
        }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    ensure
      span&.finish
    end

    sig { params(ecosystem_versions: T::Hash[Symbol, T.untyped]).void }
    def record_ecosystem_versions(ecosystem_versions)
      api_url = "#{base_url}/update_jobs/#{job_id}/record_ecosystem_versions"
      body = {
        data: { ecosystem_versions: ecosystem_versions }
      }
      response = http_client.post(api_url, json: body)
      raise ApiError, response.body if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      retry_count ||= 0
      retry_count += 1
      raise if retry_count > 3

      sleep(rand(3.0..10.0))
      retry
    end

    sig { params(metric: String, tags: T::Hash[String, String]).void }
    def increment_metric(metric, tags:)
      span = ::Dependabot::OpenTelemetry.tracer&.start_span("increment_metric", kind: :internal)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::JOB_ID, job_id)
      span&.set_attribute(::Dependabot::OpenTelemetry::Attributes::METRIC, metric)
      tags.each do |key, value|
        span&.set_attribute(key, value)
      end

      api_url = "#{base_url}/update_jobs/#{job_id}/increment_metric"
      body = {
        data: {
          metric: metric,
          tags: tags
        }
      }
      response = http_client.post(api_url, json: body)
      # We treat metrics as fire-and-forget, so just warn if they fail.
      Dependabot.logger.debug("Unable to report metric '#{metric}'.") if response.code >= 400
    rescue HTTP::ConnectionError, OpenSSL::SSL::SSLError
      Dependabot.logger.debug("Unable to report metric '#{metric}'.")
    ensure
      span&.finish
    end

    private

    sig { returns(String) }
    attr_reader :base_url

    sig { returns(T.any(String, Integer)) }
    attr_reader :job_id

    sig { returns(String) }
    attr_reader :job_token

    sig { returns(T.untyped) }
    def http_client
      client = HTTP::Client.new.auth(job_token)
      proxy = ENV["HTTPS_PROXY"] ? URI(T.must(ENV["HTTPS_PROXY"])) : URI(base_url).find_proxy
      unless proxy.nil?
        args = T.unsafe([proxy.host, proxy.port, proxy.user, proxy.password].compact)
        client = client.via(*args)
      end
      client
    end

    sig { params(dependency_change: Dependabot::DependencyChange).returns(T::Hash[String, T.untyped]) }
    def dependency_group_hash(dependency_change)
      return {} unless dependency_change.grouped_update?

      # FIXME: We currently assumpt that _an attempt_ to send a DependencyGroup#id should
      # result in the `grouped-update` flag being set, regardless of whether the
      # DependencyGroup actually exists.
      { "dependency-group": dependency_change.dependency_group.to_h }.compact
    end

    sig do
      params(dependency_change: Dependabot::DependencyChange,
             base_commit_sha: String).returns(T::Hash[String, T.untyped])
    end
    def create_pull_request_data(dependency_change, base_commit_sha)
      data = {
        dependencies: dependency_change.updated_dependencies.map do |dep|
          {
            name: dep.name,
            "previous-version": dep.previous_version,
            requirements: dep.requirements,
            "previous-requirements": dep.previous_requirements
          }.merge({
            version: dep.version,
            removed: dep.removed? ? true : nil
          }.compact)
        end,
        "updated-dependency-files": dependency_change.updated_dependency_files_hash,
        "base-commit-sha": base_commit_sha
      }.merge(dependency_group_hash(dependency_change))

      return data unless dependency_change.pr_message

      data["commit-message"] = dependency_change.pr_message.commit_message
      data["pr-title"] = dependency_change.pr_message.pr_name
      data["pr-body"] = dependency_change.pr_message.pr_message
      data
    end
  end
end

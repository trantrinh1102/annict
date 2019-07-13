# frozen_string_literal: true

module V3
  class UpdateStatusQuery < V3::ApplicationQuery
    def initialize(user:, gql_work_id:, status_kind:)
      @user = user
      @gql_work_id = gql_work_id
      @status_kind = status_kind
    end

    def call
      execute(query_string,
        variables: { work_id: gql_work_id, state: status_kind.upcase },
        context: { viewer: user }
      )
    end

    private

    attr_reader :user, :gql_work_id, :status_kind

    def query_string
      <<~GRAPHQL
        mutation StatusUpdate($workId: ID!, $state: StatusState!) {
          statusUpdate(input: { workId: $workId, state: $state }) {
            work {
              id
            }
          }
        }
      GRAPHQL
    end
  end
end

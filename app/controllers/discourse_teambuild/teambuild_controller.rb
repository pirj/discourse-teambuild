# frozen_string_literal: true

require_dependency 'teambuild_target'
require_dependency 'teambuild_progress_serializer'

module DiscourseTeambuild
  class TeambuildController < ApplicationController

    requires_login
    before_action :ensure_enabled

    def index
      render json: success_json
    end

    def progress
      user = params[:username].present? ? fetch_user_from_params : current_user
      targets = TeambuildTarget.all

      completed = []

      progress = {
        user: user,
        teambuild_targets: TeambuildTarget.all,
        completed: completed
      }

      TeambuildTargetUser.where(user_id: user.id).each do |t|
        completed << "#{t.teambuild_target_id}:#{t.teambuild_target_user_id}"
      end

      render_serialized(
        progress,
        TeambuildProgressSerializer,
        rest_serializer: true,
        include_users: true
      )
    end

    def scores
      results = DB.query(<<~SQL)
        SELECT u.id,
          u.username,
          u.username_lower,
          u.uploaded_avatar_id,
          COUNT(tgb.id) AS score,
          RANK() OVER (ORDER BY COUNT(tgb.id) DESC) AS rank
        FROM users AS u
        INNER JOIN teambuild_goals AS tgb ON tgb.user_id = u.id
        WHERE u.moderator OR u.admin
        GROUP BY u.id, u.name, u.username, u.username_lower, u.uploaded_avatar_id
        ORDER BY score DESC, u.username
      SQL

      scores = results.map do |r|
        r.as_json.tap do |result|
          result['trophy'] = true if r.rank == 1
          result['me'] = r.id == current_user.id
          result['avatar_template'] = User.avatar_template(r.username_lower, r.uploaded_avatar_id)
          result.delete('uploaded_avatar_id')
        end
      end

      render json: { scores: scores }
    end

    def complete
      TeambuildTargetUser.create!(
        user_id: current_user.id,
        teambuild_target_id: params[:target_id].to_i,
        teambuild_target_user_id: params[:user_id].to_i
      )
      render json: success_json
    end

    def undo
      TeambuildTargetUser.where(
        user_id: current_user.id,
        teambuild_target_id: params[:target_id].to_i,
        teambuild_target_user_id: params[:user_id].to_i
      ).delete_all

      render json: success_json
    end

    protected

    def ensure_enabled
      raise Discourse::InvalidAccess.new unless SiteSetting.teambuild_enabled?
    end
  end
end

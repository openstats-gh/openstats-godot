class_name OpenstatsModels extends RefCounted

class Game:
	var rid: String
	var slug: String
	var created_at: String

	static func from(data: Dictionary) -> Game:
		var game := Game.new()
		game.rid = data.get("rid", "")
		game.slug = data.get("slug", "")
		game.created_at = data.get("createdAt", "")
		return game

class User:
	var rid: String
	var slug: String
	var display_name: String
	var created_at: String
	var avatar_url: String
	var bio_text: String

	static func from(data: Dictionary) -> User:
		var user := User.new()
		user.rid = data.get("rid", "")
		user.slug = data.get("slug", "")
		user.created_at = data.get("createdAt", "")
		user.display_name = data.get("displayName", "")
		user.avatar_url = data.get("avatarUrl", "")
		user.bio_text = data.get("bioText", "")
		return user

class GameSession:
	var rid: String
	var last_pulse: String
	var next_pulse_after: int
	var game: Game
	var user: User

	static func from(data: Dictionary) -> GameSession:
		var session := GameSession.new()
		session.rid = data.get("rid", "")
		session.last_pulse = data.get("lastPulse", "")
		session.next_pulse_after = int(data.get("nextPulseAfter", "0"))
		session.game = Game.from(data.game)
		session.user = User.from(data.user)
		return session

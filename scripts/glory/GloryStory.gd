class_name GloryStory
extends RefCounted
## The Climb's scenes: what is said, the choices, and what each choice does. Scenes are queued
## by Glory as the season unfolds and played by the hub, one at a time. Lines react to how the
## season is really going - nothing here assumes you won.


## {"lines": [[speaker, text]], "choices": [[key, label]]} for scene `id`.
static func scene(id: String) -> Dictionary:
	var g := Glory.state()
	var you: Dictionary = Glory.me()
	var last: Dictionary = g.get("last", {})
	var pos := int(last.get("position", 0))
	match id:
		"intro":
			return {"lines": [
				["title", "ROAD TO GLORY"],
				["title", "ACT I  ·  NOBODY KNOWS YOUR NAME"],
				["elliot", "Monza. Formula 3. Your first race."],
				["you", "P19."],
				["elliot", "P19. Nobody here knows your name."],
				["you", "Yet."],
				["elliot", "One more thing. Luca's our lead car. If you catch him late on, you hold position."],
				["you", "Got it."],
				["elliot", "Do you?"],
				["objective", "START P19. GET AS FAR FORWARD AS YOU CAN."],
			]}
		"monza_after":
			if g["flags"].get("orders_ignored", false):
				return {"lines": [
					["elliot", "We said hold position."],
					["you", "He was slow."],
					["elliot", "He was. Don't make a habit of it."],
					["elliot", "...People noticed, though. P19 to P%d." % pos],
				]}
			if pos > 0 and pos <= 10:
				return {"lines": [["elliot", "P19 to P%d." % pos], ["you", "Could have been more."], ["elliot", "Could have. People noticed anyway."]]}
			return {"lines": [["elliot", "Tough start."], ["you", "I know."], ["elliot", "It's a long season. Nobody remembers round one."]]}
		"theo_good_race":
			return {"lines": [
				["theo", "You had a good race."],
				["you", "Thanks."],
				["theo", "Don't let it get to your head."],
				["you", "Wasn't planning on it."],
				["theo", "Everyone's fast once."],
			]}
		"scout":
			var academy: String = Glory.ACADEMIES[Glory.ACADEMIES.keys()[int(g["season"]) % Glory.ACADEMIES.size()]]["name"]
			return {"lines": [
				["elliot", "P%d." % Glory.grid_position()],
				["you", "I know."],
				["elliot", "I'm not worried about today."],
				["you", "Then what?"],
				["elliot", "The %s sent a scout." % academy],
				["you", "Today?"],
				["elliot", "Today."],
				["you", "Of course they did."],
				["objective", "FINISH P10 OR HIGHER"],
			]}
		"scout_result":
			if g["flags"].get("objective_met", false):
				return {"lines": [["elliot", "P%d. The scout stayed until the flag." % pos], ["elliot", "They want to talk."]]}
			return {"lines": [["elliot", "The scout left at half distance."], ["you", "Great."], ["elliot", "There'll be others. Make them come back."]]}
		"academies":
			var offers := Glory.academy_offers()
			var lines: Array = [["manager", "Halfway through your first season and people are calling."]]
			var choices: Array = []
			for team_id: String in offers:
				var a: Dictionary = Glory.ACADEMIES[team_id]
				lines.append(["manager", "%s: \"%s\"" % [a["name"], a["pitch"]]])
				choices.append([team_id, "JOIN %s" % a["name"]])
			if offers.is_empty():
				lines.append(["manager", "Nobody's offering yet. Keep scoring and they will."])
			lines.append(["manager", "Or stay independent: harder road, but nobody owns your contract."])
			choices.append(["", "STAY INDEPENDENT"])
			return {"lines": lines, "choices": choices}
		"f3_end":
			var p := Glory.my_position()
			var offers: Array = g.get("offers", [])
			var lines: Array = []
			if p == 1:
				lines = [["title", "F3 CHAMPION"], ["manager", "Champion. Every F2 team wants a word."]]
			elif p <= 4:
				lines = [["manager", "P%d in the championship. Strong F2 offers on the table." % p]]
			elif p <= 10:
				lines = [["manager", "P%d. Some F2 teams are interested - midfield seats." % p]]
			elif not offers.is_empty():
				lines = [["manager", "P%d. Not what we wanted, but your name opened a door." % p]]
			else:
				lines = [["manager", "P%d. No F2 team will take the risk yet." % p], ["manager", "Another year in F3. Prove them wrong."]]
			var choices: Array = []
			for team_id: String in offers:
				var t: Array = Glory.JUNIOR_TEAMS.filter(func(row: Array) -> bool: return row[0] == team_id)[0]
				choices.append([team_id, "F2 WITH %s" % str(t[1]).to_upper()])
			choices.append(["", "ANOTHER YEAR IN F3"] if not offers.is_empty() else ["", "BACK TO F3"])
			return {"lines": lines, "choices": choices}
		"f2_open":
			return {"lines": [
				["title", "ACT II  ·  ONE STEP AWAY"],
				["engineer2", "See those twenty names?"],
				["you", "Yeah."],
				["engineer2", "Most of them won a championship somewhere."],
				["you", "What's your point?"],
				["engineer2", "You're not special anymore."],
				["title", "F2 BEGINS."],
			]}
		"f1_test":
			var team: Dictionary = Career.team(Glory.f1_suitor())
			return {"lines": [
				["manager", "%s want you at a test. A real one." % team["name"]],
				["title", "YOUR FIRST F1 TEST"],
				["elliot", "Radio check."],
				["you", "Loud and clear."],
				["elliot", "All right. You've driven this circuit hundreds of times."],
				["you", "Not in this."],
				["elliot", "Exactly. Braking points are later. Everything happens faster."],
			], "choices": [["drive", "TAKE CONTROL"]]}
		"test_result":
			var score := int(g["flags"].get("test_score", 0))
			if score >= 25:
				return {"lines": [["principal", "That was quick. Properly quick."], ["manager", "They're talking about you in the motorhome."]]}
			if score >= 12:
				return {"lines": [["principal", "Solid. You didn't put it in the wall."], ["manager", "Good enough to stay on the list."]]}
			return {"lines": [["principal", "It bit you, didn't it?"], ["you", "It's a lot of car."], ["manager", "You'll get another chance. Make the season count."]]}
		"theo_announced":
			return {"lines": [
				["title", "THEO LAURENT SIGNS FOR FORMULA ONE"],
				["reporter", "Theo Laurent has secured his Formula One future. Does that add pressure?"],
				["you", "No."],
				["reporter", "You don't think about it?"],
				["you", "Every day."],
			]}
		"final_call":
			var team: Dictionary = Career.team(Glory.f1_suitor())
			var rival := Glory.seat_rival()
			return {"lines": [
				["title", "THE FINALE"],
				["manager", "%s called." % team["name"]],
				["you", "About?"],
				["manager", "Their second seat."],
				["you", "And?"],
				["manager", "You're one of two."],
				["you", "Who's the other?"],
				["manager", "..."],
				["manager", "%s." % str(Glory.state()["field"][rival]["name"]).get_slice(" ", 0)],
				["objective", "BEAT %s IN THE FINALE" % str(Glory.state()["field"][rival]["name"]).to_upper()],
			]}
		"phone_call":
			var team: Dictionary = Career.team(str(g["f1_team"]))
			return {"lines": [
				["title", "THE PHONE CALL"],
				["you", "Hello?"],
				["principal", "Am I speaking with %s?" % str(you["name"]).capitalize()],
				["you", "Yes."],
				["principal", "This is %s. Team Principal, %s." % [Glory.principal_name(), team["name"]]],
				["principal", "..."],
				["principal", "How would you like to drive for us next season?"],
				["principal", "Still there?"],
				["you", "Yeah."],
				["principal", "Well?"],
				["you", "When do I start?"],
			], "choices": [["sign", "SIGN THE CONTRACT"]]}
		"first_day":
			return {"lines": [
				["title", "YOUR FIRST DAY AS AN F1 DRIVER"],
				["elliot", "You remember Monza?"],
				["you", "P19."],
				["elliot", "Thought you'd be out of racing six months later."],
				["you", "Thanks for believing in me."],
				["elliot", "I didn't say that."],
				["elliot", "You're on your own from here."],
			]}
		"f2_stay":
			var rival := Glory.seat_rival()
			return {"lines": [
				["manager", "They went with %s." % str(Glory.state()["field"][rival]["name"]).get_slice(" ", 0)],
				["you", "..."],
				["manager", "It's not over. One more F2 season. Make it impossible to ignore you."],
			], "choices": [["stay", "ANOTHER F2 SEASON"]]}
		"f1_season_end":
			var p := Glory.my_position()
			var offers: Array = g.get("offers", [])
			var lines: Array = [["manager", "P%d in the world championship, %d points." % [p, int(g["points"].get("me", 0))]]]
			var choices: Array = [["", "STAY AT %s" % str(Glory.my_team()["name"]).to_upper()]]
			for team_id: String in offers:
				lines.append(["manager", "%s want you." % Glory.team(team_id)["name"]])
				choices.append([team_id, "SIGN FOR %s" % str(Glory.team(team_id)["name"]).to_upper()])
			if offers.is_empty():
				lines.append(["manager", "No other offers this winter."])
			if int(you["age"]) >= 33:
				choices.append(["retire", "RETIRE"])
			return {"lines": lines, "choices": choices}
	return {"lines": []}


## Applies a choice. Returns what the hub should do next: "", "test" (start the F1 test),
## "complete" (show the Road to Glory summary).
static func choose(id: String, key: String) -> String:
	match id:
		"academies":
			Glory.choose_academy(key)
		"f3_end":
			Glory.accept_junior_offer(key)
		"f1_test":
			Glory.scene_done(id)
			return "test"
		"phone_call":
			Glory.scene_done(id)
			Glory.queue_scene("first_day")
			return ""
		"first_day":
			Glory.scene_done(id)
			return "complete"
		"f2_stay":
			Glory.stay_in_f2()
		"f1_season_end":
			if key == "retire":
				Glory.scene_done(id)
				Glory.retire()
				return ""
			Glory.next_f1_season(key)
	Glory.scene_done(id)
	return ""

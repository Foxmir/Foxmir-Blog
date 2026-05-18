---
title: 'What Does the Reward Function Depend On：$R(s)$、$R(s'')$、$R(s,a)$ 与 $R(s,a,s'')$？'
date: '2026-05-19'
---

* The immediate reward $r$ returned by the environment during a transition can depend on different pieces of information: the current state $s$, the next state $s'$, the state-action pair $(s,a)$, or the full transition $(s,a,s')$.

* In a standard MDP formulation, the reward function $R$ describes the rule by which the environment gives the immediate reward $r$. In its most general form, it can be written as $R(s,a,s')$. If the reward only depends on part of the information, it can be simplified to $R(s)$, $R(s')$, or $R(s,a)$. These simplified forms are still complete and valid descriptions in the right setting.

---

The immediate reward $r$ is the value returned by the environment during one transition. The reward function $R$ describes how the environment produces this $r$. Depending on the task, $R$ can take different forms.

| Depends on | Description | When to use it |
| ---- | --- | --- |
| $R(s)$ | Current state | When the agent needs to maintain a survival or operating state |
| $R(s')$ | Next state / resulting state | When the agent needs to reach a target or destination |
| $R(s,a)$ | State and action | For decision-making tasks: the same state requires different decisions, and the reward does not evaluate the outcome after the decision |
| $R(s,a,s')$ | Full one-step transition | When the reward is given after the action is executed, based on the actual change caused by this step. The key idea is “settlement” or “post-action accounting” |

1. **State-based reward — current state: $R(s)$**

	* The reward only depends on the state the agent is currently in. Once the agent is in a certain state, it receives the reward.
	* Examples:
		* Staying in a dangerous area gives a penalty at every step.
		* As long as the agent is alive, it receives points every second.
	* Application: **when the agent needs to maintain a survival or operating state**.
		* Bipedal robot walking（Walker2D）/ ant locomotion（Ant）：standing or staying alive at each step gives a survival reward.

2. **State-based reward — next state: $R(s')$**

	* The reward only depends on where the agent arrives after this step. Once it reaches a new state, it receives the reward.
	* Example: reaching the goal gives a positive reward; falling into a trap gives a penalty.
	* Application: **when the agent needs to reach a target or destination**.
		* FrozenLake: reaching the goal state gives $+1$ reward; reaching an ordinary tile or a hole gives $0$ reward.
		* Maze game: finding the exit gives $+100$.
		* Robot charging station / agent health recovery: reaching a charging station or medical point immediately gives an energy or health reward.

3. **State-action reward: $R(s,a)$**

	- The reward depends on “what action is taken in what state.” Even if the agent is in the same state, different actions may lead to different rewards.
	- Example: braking at a red light is rewarded; running the red light is penalized.
	- Application: **for decision-making tasks, where the same situation requires different decisions, without evaluating the outcome after the decision**.
		- Combat/game setting: when a soldier faces an enemy, attacking is rewarded, while retreating is penalized.
		- Recommendation system: if the user is underage, recommending children’s products is rewarded, while recommending adult products is penalized. This does not require considering whether the user clicks.
		- Pharmacy dispensing: under different prescription or medication-list tasks, the robot dispenses a drug. Dispensing the correct drug is rewarded; dispensing the wrong drug is penalized.

4. **Transition-based reward: $R(s,a,s')$**

	- The reward depends on the full one-step transition: which state the agent starts from, what action it takes, and which state it reaches.
	- Example: different actions may have different costs; low-cost transitions are rewarded, while high-cost transitions are penalized. Different resulting states represent different consequences.
	- Application: **when the reward is given after the action is executed, based on the actual change caused by this step**. The key idea is “**settlement / post-action accounting**”.
		- Logistics / travel planning: delivering a package or reaching a travel destination through different action plans can produce different costs, time consumption, and risks. Faster, cheaper, and safer plans receive rewards; more expensive and higher-risk plans receive penalties.
		- Stock trading: after a buy/sell action, if the asset value increases, the agent receives a reward; if the asset value decreases, it receives a penalty.
		- Medical treatment: based on the patient’s current condition, different treatment plans lead to different post-treatment physical states. Improvement is rewarded; deterioration is penalized.
		- Recommendation system: on the same page, after recommending a certain product, a user click is rewarded, while closing the page or leaving is penalized.
		- Survival scenario: after taking different actions, various indicators may change, such as food, stamina, health, and safety. If the chance of survival increases, the agent is rewarded; if it decreases, the agent is penalized.

---
title: 'Deconstructing Reward in RL'
date: '2026-05-11'
---


















## Introduction

In Reinforcement Learning (RL), "Reward" is a core concept that seems simple but is extremely prone to confusion in both theory and practice.

We often find ourselves wrestling with apparent contradictions in different contexts:
* Why does my colleague say the reward is "received when leaving state S," while a tutorial says it's "received upon arriving at state S'"?
* Why is the reward function `R(s, a, s')` in theory, but in the code of many classic environments, the reward seems to depend only on `s'`?
* When we say, "there's a reward of 100 for reaching the terminal state," when, where, and how is this reward factored into our model's calculations? Why is the discussion about it always entangled with "the value being zero"?

This article does not intend to reiterate the definition of reward. Our goal is to delve into these nuanced misunderstandings—the misconceptions jointly caused by theoretical rigor, implementation flexibility, and the association with other concepts (like V/Q functions).

We will deconstruct it step by step.

## Immediate Reward and Reward Function

* The **Reward Function, R(s, a, s')**, is a **rule or procedure** that generates a reward.
* The **Immediate Reward, r**, is **the specific numerical value** (e.g., +1 or -5) returned by this function in a single, specific transition. This specific value is calculated according to the rules of the reward function.
* In practice, we often use the terms "Reward Function," "Reward," and "Immediate Reward" interchangeably.

## What Determines the Reward Function's Dependencies?

This brings us to a core confusion: "What does R truly depend on?" The question arises because the dependencies of the reward r often differ between theory and practice. To make matters more complex, this ambiguity can be easily conflated with the different dependencies of the V and Q functions, especially since reward and value are intrinsically linked within the Bellman equation.

### From the Environment's Perspective

* **General Definition**: In a **standard MDP** environment, the reward function R is the environment's feedback on **a single, complete event (a transition)**. It **depends on three elements: s, a, s'**, and the corresponding notation for the reward function is R(s, a, s').
* **Practical Implementation**: It does not necessarily have to include all elements, meaning it depends on at most these three elements, because the reward rules of real physical environments can be incredibly varied:
    * **R depends only on (s, a)**
        - The reward function is simplified to R(s, a).
        - For example: Starting from home (s), walking ($a_1$) gives a reward of (0), but taking a car ($a_2$) gives a reward of (-5).
    * **R depends only on (s)**
        - The reward function is simplified to R(s).
        - For example: Being in a burning room (s), as long as you stay here, you receive a reward of (-1) every second (regardless of any action).
    * **R depends only on (s')**
        - The reward function is simplified to R(s').
        - For example: In a board game or a maze, there is only a reward (+100) for reaching the final destination (s').

### From the Agent's Perspective (The Bellman Equation's Perspective)

* **The agent has no choice**: Regardless of how the environment generates the reward, the agent must leverage **all available information** to make its decisions. While the notations **V(s)** and **Q(s, a)** specify the **entity** being evaluated, the process of calculating these values via the Bellman equation requires the complete set of information from the transition.
* According to the **Bellman Equation**:
    * $V(s) = E [ r + \gamma * V(s') ]$
        * The state-value V itself represents the expected value of a specific state s. This "representation" is only related to s and is independent of (a, s').
        * But to calculate V, one must know the action (a) taken from s, and which s' is reached.
    * $Q(s,a) = E [ r + \gamma * max_{a'}Q(s',a') ]$
        * The action-value Q itself represents the expected value of a specific state-action pair (s, a) and is likewise independent of (s').
        * But to calculate Q, one must know which state s' is reached.
* The **`r` inside the Bellman equation** is obtained directly from the environment according to its rules. That is, it is the numerical value of the immediate reward `r` requested from the environment for "this specific transition event." The Bellman equation does not need to know the rules by which `r` was generated from the environment's perspective; it only needs the obtained `r` to perform its calculation.

## What Simplified Phrasing Really Means

* **"The reward in state S is 10"**: This is a simplified expression.
    * **From a theoretical standpoint**, the actual meaning is that this +10 is the **immediate reward obtained from the complete experience of the transition `(S, a, S')`**. It omits the full description, "when you start from S, take action a, and successfully transition to S'."
    * **From a practical standpoint**, (we need more context) it cannot be ruled out that this is a reward truly related only to state S.

* **"We get reward XX when leaving S" / "We get reward XX upon arriving at S'"**: These two expressions might coexist (you might especially hear them from colleagues describing the same environment), leading to confusion: is the reward obtained upon leaving or upon arriving? In fact, both are simplified expressions.
    * **From the perspective of the complete reward function R's definition (the theoretical level)**, **R comes from the complete experience (s, a, s')**.
    * **From the perspective of practical implementation**, it can be very flexible, and this flexibility leads to many simplified expressions.
        1. As mentioned above, if the **reward function is R(s) or R(s')**, then it is correct for us to state that the immediate reward is received upon leaving/arriving.
        2. But if the **reward function R is of another type**, or for instance, it's R(s) but described as receiving a reward upon arriving at s' (or vice versa), then it's an incorrect description.
        3. However, in **practical, colloquial terms**, such imprecise but commonly understood expressions occur frequently. As long as it ensures that **"a single reward R is issued only once for a complete experience"** (meaning, you don't get one reward for leaving and another for arriving), it is acceptable.

## The Special Case of the Terminal Reward

### Common Misconceptions

* ❌ Because the terminal state has no next state, the reward for the terminal state is handled by attributing it to the previous state.
    * **A more precise statement is**: The terminal reward is the **immediate reward `r` returned by the environment during the complete transition event  $(s, a, s_{terminal})$ that caused the episode to end**.
    * This erroneous understanding still stems from the biased perception that "`r` is tied to a single element." The key is to recognize that "`r` is tied to the entire event," which contains various elements, complete or incomplete. Therefore, the "immediate reward of the terminal state" still conforms to our definition of immediate reward and the Bellman equation.

### A Special Terminal State?

* When we discuss the **"special terminal state"**,
    1. We need to **distinguish between two objects**:
        1. **Value**: State-value V, Action-value Q
        2. **Reward** / Immediate Reward r
    2. The **"special" dual meaning**:
        1. **For value, the value of a terminal state is always 0**.
        2. **For reward, the uniqueness of the game rules** makes the "terminal state different from other states."
            1. e.g., Chess/Mazes: 0 in the middle, 100 at the end.
            2. e.g., Adventure Games: -1 for energy consumption per step, +10 for finding an item, terminal state 1 (falling into a pit) is 0, terminal state 2 (finding treasure) is 100.
            3. e.g., CartPole: +1 for surviving, 0 at the terminal state (pole falls).
            4. e.g., Automated Trading: no reward in the middle, terminal reward fluctuates with the market.
    3. The **Bellman Equation connects** the concepts of "special terminal value" and "special terminal reward." Due to confounding factors, to understand questions like "**Is the terminal state truly special, how does this 'specialness' affect calculation, and is it so special that it transcends the Bellman equation?**", one must understand them separately and clearly.

* **The good news is: the terminal state still follows the Bellman equation**, it's just that:
    1. In special game rules, although the terminal `r` is special, it is still obtained directly from the environment according to its rules. That is, it is the immediate reward `r` for "this specific transition event." The Bellman equation does not need to know how `r` is generated from the environment's perspective; it only needs the obtained `r` to calculate. Therefore, **for the terminal state, the "special reward" does not affect the computational complexity or any logic of the Bellman equation**.
    2. For both V/Q, when performing the Bellman equation calculation:
        1. $V(s_{terminal}) = 0$, $Q(s_{terminal}, a) = 0$
        2. The value function evaluates the "expected future return." Since the terminal state has been reached, there is no "future." The episode ends, and no subsequent rewards can be obtained. Therefore, its expected future return is 0.
        3. **Is this a crude violation of the Bellman equation's rules?**
			1. One might think that since all other states follow a single calculation rule, handling the terminal state separately seems to deviate from the established protocol.
			2. But this **shouldn't be seen as a crude violation**. Instead, a better way to frame it is that the terminal state does follow the same Bellman equation rules. It's just that for this special state, we have effectively pre-calculated its future value to be zero, making it convenient to use this "exact value" for a more straightforward and efficient calculation.
        4. **How is this special treatment implemented in practice?**
            1. The good news is we don't need to use `if...else` statements or temporarily modify formulas. Mature environments have usually encapsulated this for us. We just need to define which state is the terminal state, and the environment will understand the game rules. You need almost no extra operations.
            2. When a transition leads to the end of an episode, the environment's `step()` function returns a `done=True` (or `terminated=True`) signal. This signal implies that the value of the terminal state is 0, and it is generated automatically, connecting seamlessly with the existing calculation logic.
            3. By the way, the environment internally also relies on simple statements like `if...else` to achieve the seemingly effortless effects we see on the outside


















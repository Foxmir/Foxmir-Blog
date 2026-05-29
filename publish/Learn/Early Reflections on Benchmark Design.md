---
title: 'Early Reflections on Benchmark Design'
date: '2026-05-29'
---

## I Didn’t Think Too Much at First → I Had to Reconsider My Purpose

Before I started learning PPO and SAC, I had already set myself the task of writing a final “comparison report.” I didn’t think too much about it at the time; I simply followed my previous project habit and continued pushing forward with a new algorithm on a new environment. After I finally manually completed the code implementation and full training for Walker2D-v4 on PPO and Ant-v5 on SAC, I began working on this report.

**Only then did I realize that my current situation made this comparison report difficult to carry out** — not in terms of analytical difficulty, but in terms of the value of forcing such a comparison under the current conditions. **This forced me to start taking the word “benchmark” seriously**.

**My current situation**:
1. Both algorithms belong to the AC architecture, and both are self-implemented versions of classic algorithms
2. Both environments use continuous actions
3. The same environment interaction step budget
4. The same number and values of random seeds（multiple seeds）
5. Both refer to the parameter configurations from RL SB3 Zoo
6. Neither has an additional hyperparameter-tuning budget
7. Nearly identical values for shared hyperparameters（such as learning rate, discount factor, etc. But there are also differences, such as network parameters and batch size, which will be mentioned again below）
8. Nearly identical evaluation protocols（the evaluation frequency is different: the PPO project evaluates at the end of each rollout, while SAC evaluates every ten thousand timesteps, which will be mentioned again below）

**Unfortunately, however: the two different algorithms are based on two different training environments**（Walker2D-v4 and Ant-v5）. We are not facing a situation with as close to a single controlled variable as possible. This means that, whether I want to compare the algorithms’ performance in the environment, sample efficiency, computational efficiency, stability, or other metrics, **I cannot make an interpretable conclusion**. Because you cannot attribute the difference to the algorithm itself, or to the environment itself — not to mention the differences caused by various implementation details and each algorithm’s unique hyperparameters.

---

## Let’s Put the New Plan into Action Immediately, Next Week!

I had to temporarily abandon the previous task setting and **make a new plan**.
1. **Today**, I want to write about the **experience** and **thoughts** produced by these interesting moments of “**sudden realization**”
2. **Over the next two weeks**, I plan to **formally move closer to “benchmarking”**
	1. **Repositioning**: a small-scale fixed-configuration benchmark based on Ant-v5 on PPO and Ant-v5 on SAC
	2. **The current code-engineering cost I face**: I need to re-optimize the logical details of the existing PPO implementation, consider readjusting some parameters, and then run full training again
	3. **The key point is**: I need to reduce the confounding factors that lead to differences in the results as much as possible. Simply put, I will keep everything that can be kept consistent as consistent as possible, in order to improve interpretability.（There may be more details beyond surface-level numerical consistency, which is very interesting, and I look forward to experiencing this during the comparison）
	4. **Comparison details**: for example, the main metric and so on — we need to settle these first next week, and then analyze them.（Interestingly, you can even define a “failure metric” you like, such as how many training seeds completely failed to learn）

---

## When I Try to Move Closer to Benchmarking, I Feel Dizzy and Dissatisfied in All Kinds of Ways

1. I feel dizzy because too many kinds of comparisons under different contexts can all be called benchmarks — aha? One word?
2. I feel dissatisfied in all kinds of ways because I can always easily pick out problems — this is not fair! Your conclusion is not reliable!

It was not until I started learning more, more, and more information that I corrected my feelings. Now I would say: yes!
1. **We can indeed talk about benchmarks under different contexts, but this does not automatically mean that they have the same interpretability or the same strength of causal inference**.
2. **Most of the benchmarks we face are not absolutely fair**.
	1. They are often a balance point among multiple dimensions such as interpretability, training cost, fairness, and so on
	2. **Fairness has a cost**: stronger interpretability / causal inference often requires a higher comparison cost（even an exponential cost, such as grid search）

---

## The Reality We Face Is: **Relative Fairness + Explicit Boundaries**

You have to accept this messiness and this “real-world compromise,” but that does not mean our conclusions must be messy — as long as you make the applicable boundaries of the conclusions explicit!

1. First, of course, is to **honestly** disclose the important comparison details
2. Second, of course, is to **have enough experience to understand which things will affect your boundaries, and how they will affect them**
	1. This is like the fact that humans naturally have “confirmation bias.” You do not need to deliberately make your understanding go astray, but if you are not sensitive enough to correct it, you will almost always go astray!
3. Third, **when describing your conclusion, attach a long and clear description of its boundaries**
	1. Like this: **These two algorithms, under a specific environment-version, a specific set of hyperparameters, a specific training budget, a specific evaluation protocol, and a specific metric, perform as XXX**. I think it is roughly like this.
	2. Boundaries are the prerequisite for the reliability of a conclusion! When you can provide a conclusion with clear boundaries, you do not need to be afraid that it is “not beautiful enough.” **A limited but honest conclusion is more valuable than a seemingly strong conclusion with vague boundaries**.

---

## When We Talk About Benchmarks, What Can We Compare?

Hmm. **Almost. Everything. As long as you are interested**.
* Same environment, different algorithms
* Same algorithm, different environments
* Same algorithm, different configurations
* Same algorithm, different frameworks
* ……

This is almost as broad as the question of “oh, I want to compare something” itself. But **a broad purpose does not mean loose methods**. You still need to follow fairness and scientific rigor in experimental design. This means that **different “questions” will face different design costs** — obviously, some questions are easier to answer.

**Unfortunately, however, questions that are easy to answer are not necessarily good questions worth caring about**. When I could not directly write the comparison report because of my current situation and had to update the plan, I thought: ah, two algorithms, two environments — this won’t work. Since we want to do the kind of benchmark that everyone recognizes, why not just retrain? Ah, that sounds simple: isn’t it just a matter of changing the environment name in the SAC code I just finished writing? After all, Gym uses a standard interface!（At this thought, I felt that things had suddenly taken a turn for the better）

But very soon, I realized this would not work. If I made the comparison this way, I would be doing Walker2D-v4 on SAC vs. Ant-v5 on SAC, and the comparative conclusion would reflect the differences between the two game environments — why should I care about that!（Of course, other people might care）

Clearly, for advanced learning, understanding the performance differences between different algorithms is more valuable for my later learning. So I readjusted the plan and prepared to do Ant-v5 on PPO vs. Ant-v5 on SAC. I need to go back and check the various details and parameters of the two algorithms, and I may also need to optimize the existing code in advance, but it is worth it.

---

## When Talking About Algorithm Comparison, What Are We Talking About?

1. **The same algorithm can also have multiple variants — which means the boundaries of the conclusion are different**
	1. Examples:
		1. Same algorithm, different parameters
		2. Same algorithm, different logical details
		3. Same algorithm, different budget / different preprocessing / different number of training seeds……
	2. **The class-and-instance analogy**: you may generally think that when you and your colleague talk about “standard PPO,” you are talking about exactly the same algorithm. But in fact, you are talking about a “**PPO class object**.” When this algorithm is placed into a concrete application scenario, it often means a “**PPO instance object**.” In other words, **when it is in an application scenario, the algorithm becomes concrete, unique, and begins to affect the boundaries of the conclusion**.
	3. **The calibration function of boundaries for understanding**: this means that when a benchmark enters the algorithmic area you care about, you should not only look at what the conclusion says, but also **pay attention to how much your boundaries overlap with / differ from theirs, so as to recalibrate the value of that conclusion for your current project**.

2. **Different algorithms represent different structures and characteristics**.
	1. This means they cannot simply be listed as “better algorithms / worse algorithms.” **There is almost no algorithm that can dominate all tasks**, and we should not make benchmarking bear such a burden（if you have this ambition, of course you can try, but the cost of finding it may be immeasurable）, nor should this make you feel slightly dissatisfied with algorithm benchmarks.
	2. One **pragmatic goal** you can pursue is: **matching specific algorithms with their suitable contexts**. This once again brings our attention back to the “boundaries of the conclusion.”

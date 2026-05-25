---
title: 'When Should You Normalize or Scale Rewards in Reinforcement Learning：Criteria and Common Methods'
date: '2026-05-26'
---

* For commonly used values of the discount factor $\gamma$, whether the action space is continuous or discrete: if **the absolute magnitude of single-step rewards is too large** or **the variance of single-step rewards is very high**, then as long as either condition holds, it is generally recommended to perform **reward scale adjustment**.

---

## Why

* **The reward scale directly affects the numerical scale of returns, V/Q targets, TD errors, or policy update signals, and therefore affects the stability of loss functions and gradient updates.** If the reward scale is too large or fluctuates too violently, it is more likely to cause issues such as overly large value losses, unstable gradients, and training oscillations.

* However, this is not a mandatory rule. In simple tasks, training may still work well even without reward scale adjustment. For example, numerical issues may be controlled by other techniques, such as:
	- adjusting the learning rate
	- gradient / value / reward clipping
	- advantage normalization
	- reasonable network initialization
	- adaptive scaling from the optimizer

---

## Prerequisite: From Single-Step Rewards to the Scale of V/Q Targets

* What we truly care about is **the accuracy and stability of V/Q during training**. We should reason from this perspective when judging the importance of other variables.

* **One role of $\gamma$ is to control how much future rewards contribute to the current value**
	* In infinite-horizon problems, if the single-step reward is bounded and $\gamma < 1$, then the discounted return has a finite upper bound and will not grow infinitely just because the time horizon is infinite.
	* In finite-length episodes, the return is a finite sum, so there is no convergence issue like in the infinite-horizon case. However, the numerical scale of the return is still jointly affected by three factors:
			1. the magnitude of the single-step reward
			2. the episode length
			3. the discount factor $\gamma$

* **The single-step reward, episode length, and $\gamma$ jointly determine the numerical scale of the V/Q target**
	* **A mathematical example**: when the single-step reward is constantly $r=1$ and $\gamma=0.99$:
		* If the episode has infinitely many time steps, the theoretical limit of the $V$ value is given by the sum of an infinite geometric series: $V_{max} = \frac{r}{1 - \gamma} = \frac{1}{1 - 0.99} = 100$
		* If the episode has finitely many time steps, then the $V$ value is only a truncated version of this infinite geometric series; the longer the episode, the closer it gets to this upper bound.
		* Note: mathematically speaking, if the single-step reward is unbounded, then this formula is not suitable as a global bound. But the engineering logic remains the same: the judgment still comes back to the two dimensions of “single-step reward magnitude” and “reward fluctuation.”

* **Scenario analysis**:
	1. **The single-step reward is not large, but the raw cumulative reward of one episode is large**: this may simply be because the episode is long. For example, if each step gives $+1$ and the raw cumulative reward of one episode is $10000$, then under $\gamma=0.99$, the V/Q target will not become $10000$; instead, it will be roughly limited to the scale of $100$. Therefore, this does not pose an extreme threat to the computation of V/Q.
	2. **The single-step reward itself is large**: for example, if each-step reward is $100$ and $\gamma=0.99$, then the V/Q target may approach the scale of $10000$. This may cause issues such as overly large value/Q targets, overly large losses, and overly large gradient scales, so reward scale adjustment is worth considering.
	3. **The mean of the single-step reward is not large, but very large rewards or penalties occasionally appear**: this can cause some V/Q values to suddenly become very large, leading to unstable value/Q targets and making training difficult. In this case, reward scale adjustment is also worth considering.

---

## Methods

### Method 1: Z-score Standardization of Single-Step Rewards

* The underlying formula is **Z-score standardization**, which is also commonly referred to as “reward normalization” in informal usage:

$$
r_t' = \frac{r_t - \mu_r}{\sqrt{\sigma_r^2+\epsilon}}
$$

* Unlike traditional static datasets, rewards in RL are dynamically generated through sampling. Therefore, the **Welford online algorithm** is commonly used to maintain running statistics:
	* it does not store all historical rewards;
	* it only maintains the current mean $\mu_r$, variance $\sigma_r^2$, and sample count $N$;
	* whenever a new batch / rollout is collected, the statistics are updated using **recursive update formulas**.

* In implementation, the following practice is usually followed:
	* accumulate statistics globally;
	* update the statistics only during the **sampling phase**;
	* during the training phase, use the already frozen $\mu_r,\sigma_r^2$, and do not keep updating them while training. For example, in PPO, a batch of data is collected and then trained on multiple times. If the reward-normalization parameters were updated during those repeated training passes, that would clearly be incorrect.

* **Issue**: because this method subtracts the mean in its formula, it changes the zero point of the reward. As a result, the semantic meaning of zero in the normalized reward changes.

### Method 2: Reward Scaling Based on the Discounted-Return Scale

* This method first estimates the scale of a “discounted accumulated quantity,” and then uses that scale to rescale the current reward.

1. The algorithm **maintains a forward-recursive discounted accumulated quantity**, for example: $\tilde R_t = \gamma \tilde R_{t-1} + r_t$
2. It then **maintains the running variance $\operatorname{Var}(\tilde R)$ of $\tilde R_t$, and uses it to scale the current reward**:

$$
r_t^{\text{scaled}} = \frac{r_t}{\sqrt{\operatorname{Var}(\tilde R)+\epsilon}}
$$

* If there are multiple parallel environments, each environment maintains its own $\tilde R_t$.
* When an episode ends, the corresponding environment’s $\tilde R_t$ should be reset to zero.
	* The reward at the done step should still be used to update $\tilde R_t$ and the running statistics first; after processing that step, $\tilde R_t$ is then reset to zero.
* **Note**: the symbol $\tilde R_t$ here may look similar to the return in GAE / return computation, but its meaning is completely different. It is not the training target itself; it is only a running statistic used to estimate the “discounted-return scale.”

* This method usually **only divides by the standard deviation and does not subtract the mean**, so it is more accurately described as reward scaling rather than Z-score standardization. It rescales the numerical magnitude of the reward, but does not change the semantic meaning of the reward’s zero point.

### Other Reward Scale Adjustment Methods

* **Reward clipping**: limit the reward to a fixed range, such as $[-1, 1]$. The advantage is that it can forcibly suppress extreme values; the disadvantage is that it changes the relative magnitudes between different rewards and may alter the task semantics.
* **Constant scaling**: directly set $r' = r / c$, for example dividing all rewards by 10, 100, or 1000. This is simple to implement and causes relatively small semantic changes, but the scaling coefficient must be chosen manually.
* **Nonlinear transformation**: for example, using functions such as tanh to compress very large rewards. This is suitable when rewards grow exponentially or have heavy-tailed distributions, but it significantly changes the shape of the reward.
* **Advantage normalization**: commonly used in policy gradient methods such as PPO / A2C. It normalizes the advantage rather than the reward itself; it can stabilize policy updates, but it does not directly change the original scale of the V/Q target.
* **Value / return normalization**: normalize the return or value target, such as with methods like PopArt. This handles the scale of the value target, rather than directly modifying the reward.

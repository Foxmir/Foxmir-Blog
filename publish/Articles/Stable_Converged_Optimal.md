# RL Chart Reading: Stable = Converged = Optimal?

---

## Intro

> In model training:
> 1. If variable values stabilize, is this always good news?
> 2. If the curve is stable, does it count as converged?
> 3. If it has converged, can I say it's optimal?
> 4. If it's optimal, does it perform well?
> 
> 5. My reward fluctuates wildly, but final performance is near-perfect; is it a global optimum?
> 6. If gradient norm is near-zero for long, am I at the global optimum, or stuck in a local one?
> 7. If performance stops increasing, is it the global optimum, or stuck in a local one?
> 8. High reward finally appears; should I stop training immediately? What if it drops again?

In reinforcement learning, we often encounter a specific scenario—and you might even do this yourself: you throw a chart into the group chat and ask, "Has this converged?" Everyone's chart is different, too. Some show training results, others show evaluation results or loss functions; it's a mix of everything.

Randomness is a key characteristic of reinforcement learning, which makes diagnosis difficult. At the same time, when it comes to concluding what state a metric is in, it's hard to be definitive.

Moreover, in theory, in engineering, and in daily discussions, even when everyone is using the same term, they might be referring to different things.

That’s why I prepared this video. Let’s talk about how to understand and handle these real-world engineering frictions that rarely get discussed.

I’ll present the conclusions directly on each page, accompanied by simple explanations.

Without a doubt, stability, convergence, optimality, and performance quality are four distinct concepts. But under what circumstances do these concepts hold true? If one of them holds, can the others? And why?

---

## 1. What Are We Discussing?

> * Model parameters? Training metrics? Evaluation results? → Variables on the chart
> * Goal: (Input) Optimal parameters → (Output) Best performance
> 
> 1. **Stable & Converged**: Applies to any variable, regardless of what it is.
> 2. **Optimal & Performance**: Refers to Model Parameters & Evaluation Performance.
> 	1. Optimality generally doesn't apply to other variables.
> 	2. Performance quality depends on evaluation performance, not training performance.

The terms "stable" and "converged" essentially describe changes in the object itself. It doesn't matter which variable you’re tracking—whether it’s model parameters, training metrics, or evaluation results—you can talk about whether they are stable or converged.

However, "optimality" and "performance quality" are generally discussed in relation to your target variable.
Our goal is usually to reach the best possible performance under a certain standard. The best performance corresponds to the best model parameters. If performance is optimal, the parameters must be optimal; the reverse is also true. They correspond to each other. Strictly speaking, performance refers to expected return, which we can’t actually measure in reality, so we use evaluation performance to approximate it.

Note that we are using evaluation results, not training results, to measure model performance. This is the same principle as using a test set, rather than a training set, to measure performance in supervised learning.

---

## 2.1 Dynamics: Stable & Converged | Concepts & Relations

> 1. **Concept**—Are they trending toward a fixed value?
> 	1. **Stable**: In a specific observation window/scale, the fluctuation amplitude stays small enough.
> 	2. **Converged**: In the long term, trends toward a fixed value, with fluctuation amplitude continuously trending toward 0.
> 
> 2. **Relation**:
> 	1. **Stable can be short/long-term; Converged always implies a final state**: Stability depends on the observation window; convergence does not. Even with wild, non-monotonic fluctuations in the middle, it is considered converged if it trends toward a fixed value in the long term.
> 	2. **Converged implies stable; Stable does not imply converged**:
> 		1. Example: Results fluctuate between 9.99 and 10.01 but never trend to a single value.
> 		2. Interpretation:
> 			1. Stable but not converged: Fluctuation is small but not negligible (0.02).
> 			2. Engineering perspective: "Approximate convergence" if the 0.02 fluctuation can be ignored.

The key to distinguishing stability from convergence is to see if the variable is trending toward a fixed value. This value could be one you pre-defined, or one you were completely unaware of beforehand.

If a variable has converged, it means it is infinitely approaching a fixed value in the long term, and its fluctuation amplitude is continuously shrinking toward zero. This holds true regardless of how much longer you train, or whether you zoom in or out on the chart.

Convergence points to the final state. How you get there doesn't invalidate the final state. Whether you reached it smoothly or through massive, painful fluctuations doesn't matter. As long as you satisfy the condition that the variable finally converges to a fixed value, you can confidently declare it converged.

If the variable is not trending toward a fixed value but exhibits small fluctuations—small enough to be noticed, but not small enough to be ignored—you cannot claim it has converged, but you can claim it is stable.

And this stability is explicitly related to your observation window and scale.

From the moment it becomes stable, if you continue training, it might remain stable, or it might become unstable. The entire process might have involved variance gradually decreasing, or perhaps the variance remained high and it just coincidentally arrived at a stable point.

Also, if you scale your chart, the perceived fluctuation amplitude will change. Scaling doesn't change the values, but it changes the visual effect. So, even if it is numerically stable, it might look very unstable.

Therefore, we usually look at a finalized chart, check if the numerical variation is small enough, and then declare it stable, either overall or during a specific phase.

From this, you can naturally derive the relationship: convergence implies stability, but stability doesn’t imply convergence. Don’t try to memorize this as a rule—it’s too convoluted. Just understand what stability and convergence *are*, and the relationship becomes intuitive.

Take a typical curve: a variable goes through ups and downs, eventually shrinking to fluctuate between 9.99 and 10.01, but doesn't shrink further. The final change amplitude is 0.02. This is small enough to claim it has stabilized. Furthermore, if, in practical terms, this fluctuation is negligible, we can even directly claim it has "approximate convergence" at a value of 10.

---

## 2.2 Dynamics: Stable & Converged | Practice

> 1. **Without mathematical proof, we can call it "Approximate Convergence" in engineering**:
> 	1. When observing that a variable is basically stable with minor fluctuations, if we deem the **observation window is long enough + fluctuations are meaningless** and can be ignored, it can be called "Approximate Convergence".
> 2. **Conversely**:
> 	1. If stable, but the observation window is too short: **Temporarily stable; ultimate convergence unknown**.
> 	2. If stable around a value, but the error range, while small, is not negligible in significance: **Stable, but not converged; ultimate convergence unknown**.

Following this example, let's summarize: when a curve looks pretty stable, when are you qualified to declare it converged?

Undoubtedly, strict convergence is the realm of mathematical proof. We are talking about "engineering approximate convergence" here.

It must satisfy two conditions: one, "the observation window is long enough," and two, "the remaining fluctuations have no practical significance." Missing either condition won't work. These are easy to understand.

However, in reality, people's descriptions are rougher; they often mix up "stable," "converged," and "approximate convergence." If it doesn't affect the logic of the discussion, that's fine. But in scenarios where you need to be precise, you must distinguish them.

Let's briefly mention why, when you see a loss function curve trending toward stability or even zero, you might find it harder to trust stability in reinforcement learning compared to supervised learning—and why you might be more worried that further training could increase the variance.

This is because, in reinforcement learning, the collected data distribution changes the current policy, and the policy change in turn affects the next data collection. They are mutually dependent, making training less stable. Even if a variable looks stable in a certain window now, as training continues, the mutual dependency between data and policy can amplify fluctuations or suppress them, making results difficult to predict.

---

## 3.1 Optimality: Local & Global | Underlying Presumptions

> * **Optimal & Performance**: Model Parameters & Evaluation Performance
> 	1. Optimality generally doesn't apply to other variables.
> 	2. Performance quality depends on evaluation performance, not training performance.
> 	3. There can be multiple optimal parameters.
> 
> * Concepts & Relations → How to judge the optimality of the current solution? → Practical Application

We mentioned this at the beginning of the video, and we emphasize it again here. When we talk about "optimality," we are often discussing that unique variable: model parameters. The best model performance must correspond to the best model parameters.

But "the best" does not mean "unique." There can be multiple sets of optimal model parameters. As long as they all produce the best performance, they are all optimal.

We will start with their concepts and relationships, discuss methods for determining optimality, and finally land on practical applications.

---

## 3.2 Optimality: Local & Global | Concepts & Relations

> 1. **Concept**—It’s all about the **range**
> 	1. **Local Optimum**: No better feasible solution in the vicinity, but there could be one further away.
> 	2. **Global Optimum**: No better solution anywhere in the entire allowed solution space.
> 
> 2. **Relation**: A global optimum is definitely a local optimum; a local optimum is not necessarily a global optimum.

The concepts themselves are quite straightforward.

"Optimality" is a comparative concept. It means "I am better than other model parameters."
Of the two concepts, one emphasizes the local, the other the global, corresponding to the scope in which "excellence" occurs.

The relationship is simple: the world champion is definitely the national champion, but the national champion is not necessarily the world champion.

---

## 3.3.1 Optimality: Local & Global | How to Judge Optimality?

> 1. Existence: **Mathematically**, does a global optimum exist?
> 2. Solvability: **Model/Algorithm**, can we find/approximate the mathematical optimum?
> 3. Judging current solution: **Engineering**, is our current solution the optimum? / How far are we? ⛳
> 	1. **Exhaustive comparison**
> 	2. **Structural optimality check**: Use the mathematical properties of the objective to certify the current solution.
> 		1. e.g., Unconstrained, differentiable, convex function, optimization finds gradient at 0 → Global Optimum.
> 	3. **Approximating target boundaries**: Does the target have **upper/lower bounds**, or a structure that guarantees them?

To determine optimality, three different levels of questions are mixed here, and we must separate them.

Since our goal is to learn how to read charts and diagnose, we care most about the third question. We'll skip the theoretical questions of whether a global optimum exists, whether the model has enough capacity, or whether the algorithm can approximate it.

We just want to know: is the parameter I painstakingly trained the optimal solution, or an approximate one?

There are three approaches. The names are a bit abstract, but easy to understand.

First, exhaustive comparison—brute force. Obviously, not realistic.

Second, using the mathematical properties of the optimization problem to determine optimality. Let’s take minimizing a loss function as a classic example. When minimizing a loss function without constraints, if the calculated gradient is zero, it means you have reached the lowest point of the entire function, so the current parameters are naturally the global optimum.

But note: not all loss functions satisfy this, nor does gradient zero always mean a global optimum. We just gave an example of an unconstrained, differentiable, convex function.
If there are constraints, you must check if the point satisfies them. If it does, and the gradient is zero for a differentiable convex function, then it’s a global optimum; if it doesn't satisfy constraints, the solution is excluded, so it's not optimal. Alternatively, if the optimum is not differentiable, you can't use gradients to judge optimality. Or, if your objective function is non-convex, a point with gradient zero is not necessarily a global optimum.

In summary, to use this criterion, the "optimization objective itself" must possess special mathematical structures. However, in deep neural networks—for example, in deep reinforcement learning—optimization objectives are usually highly complex and lack these nice properties of simple convex or concave functions, so this criterion is rarely useful.

Third, approximating the target boundaries. You will likely use this criterion often, so we need to explain it in detail.

There are two keywords here: "target" and "boundaries." And it must be the boundaries *of the target*.

---

## 3.3.2 Optimality: Local & Global | How to Judge Optimality?

> * **Approximating target boundaries**: **When the goal is to maximize expected return, reaching the maximum return is optimal**:
> 		1. We usually use evaluation performance to approximate expected return.
> 		2. When evaluation performance approaches the target's maximum limit, it can be considered "approximate global optimum."
> 		3. Example: The single-round maximum score for Cartpole-v1 with a 500-step limit is 500. If evaluation return is 495, and the 5-point gap is considered negligible, performance is approximately globally optimal.
> 		4. Note: Not all RL environments have return boundaries, and even if they do, the environment might not support us reaching them; in these cases, optimality cannot be judged this way.
> 
> * Must clarify: what is the target?
> 	* **Supervised Learning**: Target is "minimizing loss function (in evaluation/test set)." We seek optimality by pursuing the boundary of the loss function.
> 	* **Reinforcement Learning**: Target is "expected return." Not loss function, or gradient norm. (In rare special cases, if loss function is negative expected return, $L(\theta)=-J(\theta)$, then it can be used to judge optimality.)

In RL, we usually aim to maximize expected return. If we know this target cannot exceed a certain bound, reaching this bound means we have reached a global optimum; no other solution is better. Getting close enough to this bound means we have reached an approximate global optimum, and the remaining room for improvement is negligible.

True expected return is a theoretical concept; we can’t actually measure it. In reality, we use evaluation performance to approximate it.

In games like Cartpole, where the max score is 500 per round, if you achieve 500 points with sufficient evaluation, you have reached a global optimum. Getting near 500 means you have reached an approximate global optimum.

I can give an extreme example. Suppose in the same game, conditions remain the same, but I arbitrarily define a maximum of 2 points per round, and my training goal is to get the full score—which is 2 points. Then, obviously, you can reach 2 points with a little training. So, you can claim your parameters are globally optimal every time.

But not all RL environments have return boundaries, and even if they do, environmental randomness might not allow us to reach them. So, your expected return must have a clear boundary, *and* your algorithm or environment must support reaching or approaching it for you to use this method to judge optimality.

In supervised learning, we can also aim to "minimize the loss function on the evaluation or test set." For example, with Mean Squared Error (MSE), the theoretical lower bound is 0. If you reach this theoretical lower bound, your parameters are necessarily globally optimal.

We just emphasized that we care about the boundaries *of the target*. Therefore, when "non-target" objects reach their own boundaries, it is often of no help in judging optimality. For example, in RL algorithms, although our goal is expected return, we also collect loss function and gradient norm values. The theoretical lower bound of the gradient norm is 0, and some loss functions, like MSE, have a theoretical lower bound of 0.

In RL, the loss function is usually used at different stages of the algorithm, in different logical chains, acting as an intermediate tool to fit local samples, and it often reflects the loss value of a single batch during the "training process."
Minimizing the loss function of a single batch during training and our goal—maximizing expected return during evaluation—are not mathematically coordinated.

A gradient norm reaching a boundary of 0 may indeed be a local or global optimum, but it could also be a saddle point or a plateau. So, if it reaches a boundary, the loss function may not have reached its boundary, and the expected return is not necessarily optimal.

But of course, a gradient reaching 0 has value. As we mentioned above, when the "optimization target itself" has a specific mathematical structure, such as the unconstrained differentiable convex function mentioned earlier, a gradient of 0 can directly represent having attained a global optimum.

Now, we return to the core conclusion: in reinforcement learning, the goal is usually to maximize expected return, and reaching the maximum return constitutes a global optimum. Non-target objects don't get that treatment.

Let's refocus on the question we care about: how to judge the optimality of the current solution? We mentioned three methods: first, brute force; second, structural optimality judgment using the mathematical properties of the objective; and third, the one we just mentioned, approximating target boundaries.

Finally, when none of this evidence is sufficient—when methods one, two, and three don't apply—we cannot simply deny it's an optimal solution; we can only say it's currently undetermined.

---

## 3.4 Optimality: Local & Global | Practice

> 1. Common communication scenario: Model performance looks like **training is stuck**/**performance is stagnant** → **Local Optimum hypothesis**.
> 2. Practical goal requirement: **Pursue "Good Enough,"** use "Good Enough" as the acceptable result/stopping criterion.

In practical applications, you'll often hear others explain a chart with stagnant performance by saying, "It might be stuck in a local optimum, preventing the model from improving, and the parameters can't jump out." What do they actually mean when they say this?

First, the phenomenon is clear, and the inference that the model is in a local optimum is indeed possible, but evidence is insufficient.

A stagnant curve indicates that the training effect of current parameters has not improved further; it does not mean that there are no better parameters in the vicinity of the current parameters. It is entirely possible that there is a better parameter combination in the neighborhood—right nearby—but if we are currently at a saddle point or on a plateau, causing parameter updates to be almost non-existent, performance can also be stagnant.

Training curves only provide information about the parameters along their own path; we don't have enough information about the surrounding parameter space, so this expression is usually just a convenient mechanistic speculation.

In practical engineering, even without knowing the mechanism, you can perform speculative diagnosis: roughly guess a few of the most likely directions, then make experimental modifications, and run it again to see. We *do* hope that training can yield better results again and again. But optimality is not a necessary condition for a training result to be acceptable.

In practical engineering, we generally pursue a "good enough" result, not an optimal one. Of course, your "good enough" result could *also* be optimal, but that’s beside the point.

What is "good enough"? Simply put, it's whatever satisfies you. If, given the resources you can provide, you've reached your established standard, that’s good enough, and you can stop training. Even if there exists a set of parameters with even better performance than your defined standard, it doesn't matter, because that belongs to a different project.

---

## 4.1 Three Concept Sets: Stable/Converged, Optimal, Performance | Essence

> * Essentially, they care about **three different questions**:
> 	1. **Stable & Converged**: Trend of a variable over time → **How is it changing?**
> 		* Converged implies stable; stable does not imply converged.
> 	2. **Optimality**: Comparability between different solutions → **Is it the best?**
> 		* Global optimum implies local optimum; local optimum does not imply global optimum.
> 	3. **Performance**: Is expected return meeting human-set standards → **Is it up to standard?**

We know more concepts now; we’ve grouped them into three pairs. Can these concept groups be inferred from one another? If I hold true, does that mean you must hold true? This section is very practical.

Although the concept of "performance quality" wasn't explained separately above, it’s worth including here. It means exactly what it says literally: in our given scenario and under our given standards, meeting or approaching the standard is good performance; conversely, it’s bad performance.

These three sets of concepts care about three different questions.

Stability and convergence care about the trend of variables over time.
Optimality cares about the comparability between different solutions.
Performance quality cares about whether expected return has reached a human-set standard.

When you want to know the dependency between concepts, you are actually checking whether you can answer the corresponding question based on the information you have. We'll derive this by starting with some common intuitive errors.

---

## 4.2 Three Concept Sets: Stable/Converged, Optimal, Performance | Common False Intuitions

> 1. ❌ Stable / Converged, Optimal → Must be "Good Performance."
> 2. ❌ Stable, Converged, Training Stagnant → Must be at least a Local Optimum.
> 3. ❌ Global Optimum, No Room to Improve → Continuing training will maintain optimal performance.

The most common intuitive error is when you hear someone report that their training results are stable or converged, or even say they have reached a local optimum or a global optimum; this doesn't necessarily mean good news—their training might be far from over. There is no information here to answer whether the set standard has been met, so it’s not necessarily good performance.

If the model’s capacity is insufficient, even if we reach the model's capability limit, the solution might still be terrible.

The second common intuitive misunderstanding, which we mentioned when discussing the application of optimality, is that a local optimum is one possible mechanism for this stability or stagnation, but not the only one.

Now, let's look at it from another angle. If training has lasted a long time, it enables you to answer the question, "How does training return change over time?" But it hasn't compared the current parameters with other parameters in the surrounding space, so you cannot answer, "Is the current parameter the best in the surrounding space?" So the second statement is also wrong.

Now, assume you really have reached a global optimum—you’ve found the best solution in the solution space, and there is absolutely no room for improvement. If you continue training, will the model performance remain excellent?

Global optimality answers the question of what is best in the current solution space. Whether it can be maintained in subsequent training depends on how other factors related to it change over time, such as environmental information, sample distribution, sampling error, noise level, and we just don't have that info. Subsequent training itself does not automatically provide performance guarantees; the expected return might remain globally optimal, or performance might decline. So, this statement is obviously wrong, too.

---

## 5.1 Review | Questions

> In model training:
> 1. If variable values stabilize, is this always good news?
> 2. If the curve is stable, does it count as converged?
> 3. If it has converged, can I say it's optimal?
> 4. If it's optimal, does it perform well?
> 
> 5. My reward fluctuates wildly, but final performance is near-perfect; is it a global optimum?
> 6. If gradient norm is near-zero for long, am I at the global optimum, or stuck in a local one?
> 7. If performance stops increasing, is it the global optimum, or stuck in a local one?
> 8. High reward finally appears; should I stop training immediately? What if it drops again?

At this point, the main text is over. For fun, let's look at the questions from the intro. You should feel they are very clear and easy to judge now.

Feel free to pause for a few seconds and think about them. The final two pages will present the answers as text.

---

## 5.2 Review | Questions & Answers 1/2

> 1. If variable values stabilize, is this always good news? — Not necessarily; it could be stable at poor performance.
> 2. If the curve is stable, does it count as converged? — Not necessarily; it depends on whether it converged to a fixed value / or if the fluctuation is negligible.
> 3. If it has converged, can I say it's optimal? — Not necessarily; it no longer changes over time, but that doesn't mean there aren't better solutions around it.
> 4. If it's optimal, does it perform well? — Not necessarily; it could be a bad model, where the maximum score of a bad model is still bad performance.
> 
> 5. My reward fluctuates wildly, but final performance is near-perfect; is it a global optimum? — Yes, but more accurately, an "approximate global optimum." It is currently the best solution, which is independent of the intermediate process.
> 6. If the gradient norm remains near zero for a long time, am I at a local or global optimum? — Not necessarily. For a non-convex function, having a zero (or near-zero) gradient may simply mean you are at a saddle point or on a plateau—not even at a local optimum. Even if you are genuinely at a local optimum, without information about the landscape farther away, you cannot infer global optimality. However, for an unconstrained, differentiable convex loss function, a gradient of zero does certify a global optimum for the loss.
> 7. If performance stops increasing, is it the global optimum, or stuck in a local one? — **Not necessarily either one.** Just because performance is stagnant doesn't mean your solution is better than surrounding ones.

---

## 5.3 Review | Questions & Answers 2/2

> 8. High reward finally appears; should I stop training immediately? What if it drops again?
> 	1. As long as the goal is achieved, you are qualified to stop. The key isn't whether the curve looks pretty or stable, but whether your goal is met. (Whether your goal setting is reasonable is a different matter.)
> 	2. If you don't just care about a single high reward, but expect training to yield more high rewards, or more stable high rewards, your goal itself should include requirements such as average round return, high-score ratio, standard deviation/variance, etc. It depends on your specific needs.
> 	3. Whatever your goal, continuing training may lead to performance decline, but that doesn't necessarily threaten the current goal.
> 		1. If you keep the current model and its usage fixed, if the environment and evaluation conditions also remain the same, then the expected return naturally remains the same (though single-evaluation results may still fluctuate).
> 		2. If you guarantee using the current version of model parameters, but the environment or evaluation criteria keep changing, maintaining good performance is difficult. If you have such stability requirements, you can pursue a robustness goal across multiple environments and conditions from the start.

---
title: "The First Title"   <-- 这里控制网页显示的大标题
author: "Foxmir"
date: "2026-01-16"
---

# The first title

## 1. 测试 LaTeX 公式

这是行内公式：我们在讨论 $E = mc^2$ 的物理意义。

这是行间公式（应该居中显示）：
$$
f(x) = \int_{-\infty}^\infty \hat f(\xi)\,e^{2\pi i \xi x} \,d\xi
$$

## 2. 测试 Python 代码高亮

下面是一段 Python 代码：

```python
import numpy as np
import matplotlib.pyplot as plt

def plot_wave(freq):
    x = np.linspace(0, 10, 100)
    y = np.sin(freq * x)
    return x, y

print("Hello Quarto!")
```
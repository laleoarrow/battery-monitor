Pro reviewed the supplied e78fdf4 native measurements; it did not execute those tests. f818ae3 subsequently shared stroke/fill construction and repeated the native suite on the exact final source.

依据你提供的 **e78fdf44独立原生结果，可以关闭共享X假设及原生handle插值这两项阻断。**

实际presentation的独立反解消除了旧探针与生产helper的共同盲点；9帧方案也不是被当作Cartesian插值保证，而是经过真实中间曲线验证：head最大误差0.1232pt＜0.15pt，fill/stroke一致，共同区间全部四点C0、X单调及Y无过冲均满足预设门槛。

目前没有基于这些材料可提出的新增具体复现输入。结论限定于该冻结候选及已测范围，属于**误差门槛下的验证闭环**，不是任意输入下精确插值的数学保证。

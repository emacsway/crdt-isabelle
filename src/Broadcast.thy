section\<open>Implementation of Causal Broadcast Protocol\<close>

theory
  Broadcast
imports
  Execution
  Network
  Util
begin

subsection\<open>Causal broadcasts using vector timestamps\<close>

type_synonym 'nodeid msgid = "'nodeid \<times> nat"

record ('nodeid, 'op) message =
  msg_id   :: "'nodeid msgid"
  msg_deps :: "'nodeid \<Rightarrow> nat"
  msg_op   :: "'op"

type_synonym ('nodeid, 'op) node_state = "(('nodeid, 'op) message event, unit) node"

definition filter_bcast :: "('nodeid, 'op) message event list \<Rightarrow> ('nodeid, 'op) message list" where
  "filter_bcast evts \<equiv> List.map_filter (\<lambda>e. case e of Broadcast m \<Rightarrow> Some m | _ \<Rightarrow> None) evts"

definition filter_deliv :: "('nodeid, 'op) message event list \<Rightarrow> ('nodeid, 'op) message list" where
  "filter_deliv evts \<equiv> List.map_filter (\<lambda>e. case e of Deliver m \<Rightarrow> Some m | _ \<Rightarrow> None) evts"

definition causal_deps :: "('nodeid, 'op) node_state \<Rightarrow> 'nodeid \<Rightarrow> nat" where
  "causal_deps state \<equiv> foldl
    (\<lambda>map msg. case msg_id msg of (node, seq) \<Rightarrow> map(node := seq))
    (\<lambda>n. 0) (filter_deliv (fst state))"

definition deps_leq :: "('nodeid \<Rightarrow> nat) \<Rightarrow> ('nodeid \<Rightarrow> nat) \<Rightarrow> bool" where
  "deps_leq left right \<equiv> \<forall>node::'nodeid. left node \<le> right node"

definition causally_ready :: "('nodeid, 'op) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> bool" where
  "causally_ready state msg \<equiv>
     deps_leq (msg_deps msg) (causal_deps state) \<and>
     (case msg_id msg of (sender, seq) \<Rightarrow> seq = Suc(causal_deps state sender))"

definition next_msgid :: "'nodeid \<Rightarrow> ('nodeid, 'op) node_state \<Rightarrow> 'nodeid msgid" where
  "next_msgid sender state \<equiv> (sender, Suc (length (filter_bcast (fst state))))"

definition valid_msgs :: "(('nodeid, 'op) node_state \<Rightarrow> 'op set) \<Rightarrow> 'nodeid \<Rightarrow> ('nodeid, 'op) node_state \<Rightarrow> ('nodeid, 'op) message set" where
  "valid_msgs valid_ops sender state \<equiv>
     (\<lambda>oper. \<lparr>msg_id   = next_msgid sender state,
              msg_deps = causal_deps state,
              msg_op   = oper\<rparr>
     ) ` valid_ops state"

definition protocol_send ::
  "'nodeid \<Rightarrow> ('nodeid, 'op) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> ('nodeid, 'op) node_state" where
  "protocol_send sender state msg \<equiv> ([Broadcast msg, Deliver msg], ())"

definition protocol_recv ::
  "'nodeid \<Rightarrow> ('nodeid, 'op) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> ('nodeid, 'op) node_state" where
  "protocol_recv recipient state msg \<equiv>
     if causally_ready state msg then ([Deliver msg], ()) else ([], ())"

locale cbcast_protocol_base = executions "\<lambda>n. ()" valid_msg protocol_send protocol_recv
  for valid_msg :: "nat \<Rightarrow> (nat, 'op) message event list \<times> unit \<Rightarrow> (nat, 'op) message set" +
  fixes valid_ops :: "(nat, 'op) node_state \<Rightarrow> 'op set"

locale cbcast_protocol = cbcast_protocol_base "valid_msgs valid_ops" valid_ops
  for valid_ops :: "(nat, 'op) message event list \<times> unit \<Rightarrow> 'op set" +
  fixes config :: "(nat, (nat, 'op) message, (nat, 'op) message event, unit) system"
  assumes valid_execution: "execution config"

definition (in cbcast_protocol) history :: "nat \<Rightarrow> (nat, 'op) message event list" where
  "history i \<equiv> fst (snd config i)"

definition (in cbcast_protocol) all_messages :: "(nat, 'op) message set" where
  "all_messages \<equiv> fst config"

definition (in cbcast_protocol) broadcasts :: "nat \<Rightarrow> (nat, 'op) message list" where
  "broadcasts i \<equiv> List.map_filter (\<lambda>e. case e of Broadcast m \<Rightarrow> Some m | _ \<Rightarrow> None) (history i)"

definition (in cbcast_protocol) deliveries :: "nat \<Rightarrow> (nat, 'op) message list" where
  "deliveries i \<equiv> List.map_filter (\<lambda>e. case e of Deliver m \<Rightarrow> Some m | _ \<Rightarrow> None) (history i)"


subsection\<open>Proof that this protocol satisfies the causal network assumptions\<close>

lemma (in cbcast_protocol) broadcast_origin:
  assumes "history i = xs @ Broadcast msg # ys"
    and "Broadcast msg \<notin> set xs"
  shows "\<exists>pre before after suf oper evts.
    config_evolution config (pre @ [before, after] @ suf) \<and>
    oper \<in> valid_ops (snd before i) \<and>
    msg = \<lparr>msg_id   = next_msgid i (snd before i),
           msg_deps = causal_deps (snd before i),
           msg_op   = oper\<rparr> \<and>
    evts = fst (snd before i) @ [Broadcast msg, Deliver msg] \<and>
    after = (insert msg (fst before), (snd before)(i := (evts, ()))) \<and>
    fst (snd before i) = xs"
  using assms valid_execution apply -
  apply(frule config_evolution_exists, erule exE)
  apply(subgoal_tac "Broadcast msg \<in> set (fst (snd config i))") defer
  apply(simp add: history_def)
  apply(frule_tac evt="Broadcast msg" and i=i and xs=xs and ys=ys in event_origin)
  apply(simp add: history_def, simp)
  apply((erule exE)+, (erule conjE)+)
  apply(rule_tac x=pre in exI, erule disjE)
  apply(simp add: send_step_def case_prod_beta)
  apply(erule unpack_let)+
  apply(simp add: case_prod_beta protocol_send_def split: if_split_asm)
  apply(erule unpack_let)
  apply(subgoal_tac "sender=i") prefer 2 apply force
  apply(subgoal_tac "fst (snd after i) = fst (snd before i) @ [Broadcast msga, Deliver msga]")
  prefer 2 apply force
  apply(subgoal_tac "msga=msg") prefer 2 apply simp
  apply(subgoal_tac "msg \<in> valid_msgs valid_ops i (snd before i)")
  prefer 2 apply(simp add: some_set_memb)
  apply(rule_tac x="fst before" in exI, rule_tac x="snd before" in exI)
  apply(rule_tac x="fst after" in exI, rule_tac x="snd after" in exI)
  apply(rule conjI, force)
  apply(rule_tac x="msg_op msg" in exI)
  apply(subgoal_tac "valid_ops (snd before i) \<noteq> {}")
  prefer 2 apply(simp add: valid_msgs_def)
  apply(subgoal_tac "msg \<in> (\<lambda>oper.
             \<lparr>msg_id   = next_msgid i (snd before i),
              msg_deps = causal_deps (snd before i),
              msg_op   = oper\<rparr>) ` valid_ops (snd before i)")
  prefer 2 apply (simp add: valid_msgs_def)
  apply(subgoal_tac "msg_op msg \<in> valid_ops (snd before i)")
  prefer 2 apply force
  apply((rule conjI, force)+, force)
  apply(simp add: recv_step_def protocol_recv_def case_prod_beta split: if_split_asm)
  apply(erule unpack_let)+
  apply(subgoal_tac "recipient=i")
  apply force+
done

lemma (in cbcast_protocol) broadcast_msg_eq:
  shows "(\<exists>i. Broadcast msg \<in> set (history i)) \<longleftrightarrow> msg \<in> all_messages"
  apply(simp add: all_messages_def)
  apply(rule iffI, erule exE)
  apply(subgoal_tac "\<exists>es1 es2. history i = es1 @ Broadcast msg # es2 \<and> Broadcast msg \<notin> set es1")
  prefer 2 apply(meson split_list_first)
  apply((erule exE)+, erule conjE)
  apply(drule broadcast_origin, simp, (erule exE)+, (erule conjE)+)
  apply(subgoal_tac "msg \<in> fst after")
  apply(insert message_set_monotonic)[1]
  apply(erule_tac x="config" in meta_allE)
  apply(erule_tac x="pre @ [before]" in meta_allE, simp, simp)
  apply(insert valid_execution, drule config_evolution_exists, erule exE)
  apply(drule message_origin, simp, (erule exE)+, (erule conjE)+)
  apply(rule_tac x=sender in exI)
  apply(subgoal_tac "Broadcast msg \<in> set (fst (snd config sender))")
  apply(simp add: history_def)
  apply(subgoal_tac "\<exists>xs. fst (snd after sender) @ xs = fst (snd config sender)")
  apply(simp add: protocol_send_def, metis in_set_conv_decomp)
  apply(insert history_monotonic)[1]
  apply(erule_tac x="config" in meta_allE)
  apply(erule_tac x="pre @ [before]" in meta_allE)
  apply(erule_tac x="after" in meta_allE)
  apply(erule_tac x="suf" in meta_allE)
  apply(erule_tac x="sender" in meta_allE, simp)
done

lemma (in cbcast_protocol) map_filter_broadcast:
  assumes "msg \<in> set (filter_bcast hist)"
  shows "Broadcast msg \<in> set hist"
  using assms apply(induction hist)
  apply(simp add: filter_bcast_def map_filter_simps(2))
  apply(case_tac a, case_tac "x1=msg")
  apply(metis list.set_intros(1))
  apply(simp_all add: filter_bcast_def map_filter_simps(1))
done

lemma (in cbcast_protocol) broadcasts_history_eq:
  shows "Broadcast msg \<in> set (history i) \<longleftrightarrow> msg \<in> set (broadcasts i)"
  apply(rule iffI, simp add: broadcasts_def map_filter_def, force)
  apply(simp add: broadcasts_def filter_bcast_def map_filter_broadcast)
done

lemma (in cbcast_protocol) broadcast_node_id:
  assumes "Broadcast msg \<in> set (history i)"
  shows "fst (msg_id msg) = i"
  using assms apply -
  apply(subgoal_tac "\<exists>es1 es2. history i = es1 @ Broadcast msg # es2 \<and> Broadcast msg \<notin> set es1")
  prefer 2 apply(meson split_list_first)
  apply((erule exE)+, erule conjE, drule broadcast_origin)
  apply(simp, simp add: next_msgid_def)
  apply(metis fst_conv select_convs(1))
done

lemma (in cbcast_protocol) broadcast_msg_id:
  assumes "history i = pre @ [Broadcast msg] @ suf"
      and "Broadcast msg \<notin> set pre"
    shows "msg_id msg = (i, Suc (length (filter_bcast pre)))"
  using assms valid_execution apply simp
  apply(frule config_evolution_exists, erule exE)
  apply(subgoal_tac "Broadcast msg \<in> set (history i)") defer
  using map_filter_broadcast apply force
  apply(drule broadcast_origin, simp, (erule exE)+)
  apply(simp add: next_msgid_def)
done

lemma bcast_append_length:
  shows "length (filter_bcast (xs @ ys)) =
     length (filter_bcast (xs)) + length (filter_bcast (ys))"
by(simp add: filter_bcast_def map_filter_append)

lemma (in cbcast_protocol) msg_id_distinct:
  assumes "Broadcast m1 \<in> set (history j)"
    and "Broadcast m2 \<in> set (history j)"
    and "msg_id m1 = msg_id m2"
  shows "m1 = m2"
  using assms apply -
  apply(drule_tac x="Broadcast m1" in list_first_index)
  apply(drule_tac x="Broadcast m2" in list_first_index)
  apply((erule_tac exE)+, (erule_tac conjE)+)
  apply(subgoal_tac "msg_id m1 = (j, Suc (length (filter_bcast pre)))")
  prefer 2 apply(metis broadcast_msg_id)
  apply(subgoal_tac "msg_id m2 = (j, Suc (length (filter_bcast prea)))")
  prefer 2 apply(metis broadcast_msg_id)
  apply(subgoal_tac "length (filter_bcast pre) = length (filter_bcast prea)")
  prefer 2 apply simp
  apply(case_tac "i = ia", fastforce)
  apply(case_tac "i < ia")
  apply(subgoal_tac "\<exists>ms. prea = pre @ [Broadcast m1] @ ms", erule exE)
  apply(subgoal_tac "length (filter_bcast prea) =
    length (filter_bcast pre) + 1 + length (filter_bcast ms)", linarith)
  apply(subgoal_tac "length (filter_bcast [Broadcast m1]) = 1")
  prefer 2 apply(simp add: filter_bcast_def map_filter_def)
  apply(metis (no_types, lifting) bcast_append_length add.assoc)
  apply(subgoal_tac "pre = take i (history j)")
  prefer 2 apply(simp add: append_eq_conv_conj)
  apply(subgoal_tac "prea = take ia (history j)")
    prefer 2 apply fastforce
  apply(subgoal_tac "ia-i-1 \<ge> 0") prefer 2 apply blast
  apply(rule_tac x="take (ia-i-1) suf" in exI)
  apply(metis append.left_neutral append_Cons diff_is_0_eq diffs0_imp_equal
    less_imp_le_nat take_Cons' take_all take_append)
  apply(subgoal_tac "\<exists>ms. pre = prea @ [Broadcast m2] @ ms", erule exE)
  apply(subgoal_tac "length (filter_bcast pre) =
    length (filter_bcast prea) + 1 + length (filter_bcast ms)", linarith)
  apply(subgoal_tac "length (filter_bcast [Broadcast m2]) = 1")
  prefer 2 apply(simp add: filter_bcast_def map_filter_def)
  apply(metis (no_types, lifting) bcast_append_length add.assoc)
  apply(subgoal_tac "pre = take i (history j)")
  prefer 2 apply(simp add: append_eq_conv_conj)
  apply(subgoal_tac "prea = take ia (history j)")
    prefer 2 apply fastforce
  apply(subgoal_tac "i-ia-1 \<ge> 0") prefer 2 apply blast
  apply(rule_tac x="take (i-ia-1) sufa" in exI)
  apply(metis One_nat_def Suc_diff_Suc append_Cons append_Nil diff_zero less_imp_le_nat
    linorder_neqE_nat take_Suc_Cons take_all take_append zero_less_diff)
done

lemma (in cbcast_protocol) msg_id_unique:
  assumes "Broadcast m1 \<in> set (history i)"
      and "Broadcast m2 \<in> set (history j)"
      and "msg_id m1 = msg_id m2"
    shows "i = j \<and> m1 = m2"
  using assms apply -
  apply(case_tac "i=j")
  using msg_id_distinct apply blast
  apply(subgoal_tac "fst (msg_id m1) = i")
  apply(subgoal_tac "fst (msg_id m2) = j", force)
  using broadcast_node_id apply fastforce+
done

context cbcast_protocol begin
sublocale causal: causal_network history msg_id
  apply standard
  prefer 4 apply(simp add: msg_id_unique)
  oops

end

end
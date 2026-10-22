import sys
import xml.etree.ElementTree as ET
from pathlib import Path


plan_path = Path(__file__).with_name("dynamics-crm.jmx")
root = ET.parse(plan_path).getroot()
if root.tag != "jmeterTestPlan" or root.get("jmeter") != "5.6.3":
    sys.exit("Expected a JMeter 5.6.3 test plan.")


def validate_hash_tree(tree):
    children = list(tree)
    if len(children) % 2:
        sys.exit("Every JMeter test element must have a following hashTree.")

    for index in range(0, len(children), 2):
        element, child_tree = children[index:index + 2]
        if child_tree.tag != "hashTree":
            sys.exit(f"{element.tag} is not followed by a hashTree.")
        validate_hash_tree(child_tree)


validate_hash_tree(root.find("hashTree"))

elements = list(root.iter())
script_elements = [
    element
    for element in elements
    if element.tag in {"JSR223Sampler", "JSR223PostProcessor"}
]
for element in script_elements:
    script = element.findtext("stringProp[@name='script']") or ""
    if "${__GetSecret(" in script:
        sys.exit("Do not embed a literal GetSecret expression inside a JMeter script.")

secret_arguments = [
    element
    for element in elements
    if element.tag == "elementProp"
    and element.get("name") == "CRM_CLIENT_SECRET"
    and element.get("elementType") == "Argument"
]
if (
    len(secret_arguments) != 1
    or secret_arguments[0].findtext("stringProp[@name='Argument.value']")
    != "${__GetSecret(dynamicsCrmClientSecret)}"
):
    sys.exit("CRM_CLIENT_SECRET must use the Azure Load Testing GetSecret function.")

samplers = {
    element.get("testname"): element
    for element in elements
    if element.tag == "HTTPSamplerProxy"
}
required_samplers = {
    "Acquire Dynamics access token": "POST",
    "Lookup contact by email or telephone": "GET",
    "Create contact": "POST",
    "Create phone call associated with contact": "POST",
    "Update phone call after wait": "PATCH",
}
for name, method in required_samplers.items():
    sampler = samplers.get(name)
    if sampler is None or sampler.findtext("stringProp[@name='HTTPSampler.method']") != method:
        sys.exit(f"Missing or incorrect HTTP sampler: {name} ({method}).")

thread_group = next(element for element in elements if element.tag == "ThreadGroup")
if thread_group.findtext(
    "elementProp[@name='ThreadGroup.main_controller']/stringProp[@name='LoopController.loops']"
) != "${__P(ITERATIONS,1)}":
    sys.exit("Thread group must use the ITERATIONS JMeter property.")
if thread_group.findtext("stringProp[@name='ThreadGroup.num_threads']") != "${__P(VUS,1)}":
    sys.exit("Thread group must use the VUS JMeter property.")

assertions = [
    element for element in elements if element.tag == "ResponseAssertion"
]
if len(assertions) != 5:
    sys.exit("Expected response assertions for the token and all four CRM requests.")

header_managers = [
    element for element in elements if element.tag == "HeaderManager"
]
for manager in header_managers:
    headers = manager.find("collectionProp[@name='HeaderManager.headers']")
    if headers is None or any(
        header.tag != "elementProp" or header.get("elementType") != "Header"
        for header in headers
    ):
        sys.exit("HTTP header manager contains malformed header definitions.")

timers = [element for element in elements if element.tag == "UniformRandomTimer"]
if len(timers) != 1:
    sys.exit("Expected exactly one randomized wait timer.")
timer = timers[0]
test_tree_parents = {}


def index_test_tree(tree, parent_element=None):
    children = list(tree)
    for index in range(0, len(children), 2):
        element, child_tree = children[index:index + 2]
        test_tree_parents[element] = parent_element
        index_test_tree(child_tree, element)


index_test_tree(root.find("hashTree"))
timer_controller = test_tree_parents.get(timer)
if (
    timer_controller is None
    or timer_controller.get("testname") != "Wait and update phone call"
    or test_tree_parents.get(samplers["Update phone call after wait"]) is not timer_controller
):
    sys.exit("The randomized wait must apply only to the phone call update.")
if timer.findtext("stringProp[@name='ConstantTimer.delay']") != "60000":
    sys.exit("Wait timer must have a 60-second base delay.")
if timer.findtext("stringProp[@name='RandomTimer.range']") != "60000":
    sys.exit("Wait timer must add up to 60 seconds of random delay.")

print("JMeter test plan XML and required CRM load-test steps are valid.")

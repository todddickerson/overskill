import { Application } from "@hotwired/stimulus"
import { controllerDefinitions as bulletTrainControllers } from "@bullet-train/bullet-train"
import { controllerDefinitions as bulletTrainFieldControllers } from "@bullet-train/fields"
import { controllerDefinitions as bulletTrainSortableControllers } from "@bullet-train/bullet-train-sortable"
import ScrollReveal from 'stimulus-scroll-reveal'
import RevealController from 'stimulus-reveal'
import CableReady from 'cable_ready'
import consumer from '../channels/consumer'

const application = Application.start()

// In the browser console:
// * Type `window.Stimulus.debug = true` to log actions and lifecycle hooks
//   on subsequent user interactions and Turbo page views.
// * Type `window.Stimulus.router.modulesByIdentifier` for a list of loaded controllers.
// See https://stimulus.hotwired.dev/handbook/installing#debugging
window.Stimulus = application

// Load all the controllers within this directory and all subdirectories.
// Controller files must be named *_controller.js.
import { context as controllersContext } from './**/*_controller.js';

application.register('reveal', RevealController)
application.register('scroll-reveal', ScrollReveal)

// Helper function to convert filename to identifier (esbuild compatible)
function identifierForContextKey(key) {
  const logicalName = key
    .replace(/^\.\//, '')
    .replace(/_controller\.(js|ts)$/, '')
    .replace(/\//g, '--')
    .replace(/_/g, '-')
  return logicalName
}

let controllers = Object.keys(controllersContext).map((filename) => ({
  identifier: identifierForContextKey(filename),
  controllerConstructor: controllersContext[filename] }))

// Debug logging
console.log('Loading controllers:', controllers.map(c => c.identifier))

controllers = overrideByIdentifier([
  ...bulletTrainControllers,
  ...bulletTrainFieldControllers,
  ...bulletTrainSortableControllers,
  ...controllers,
])

application.load(controllers)

// Log all registered controllers
console.log('Registered Stimulus controllers:', Object.keys(application.router.modulesByIdentifier))

CableReady.initialize({ consumer })

function overrideByIdentifier(controllers) {
  const byIdentifier = {}

  controllers.forEach(item => {
    byIdentifier[item.identifier] = item
  })

  return Object.values(byIdentifier)
}
